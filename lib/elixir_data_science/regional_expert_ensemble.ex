defmodule ElixirDataScience.RegionalExpertEnsemble do
  @moduledoc """
  Evidence-first point-in-time regional ensemble primitives.

  Source receipts, normalized observations, panels, predictions, and fitted
  model state are generated artifacts and remain outside Git.
  """

  @contract_path Path.expand("../../contracts/regional-expert-ensemble.v1.json", __DIR__)
  @research_cutoff ~D[2026-08-29]
  @source_hosts %{"qcew" => "bls.gov", "bea" => "bea.gov", "fhfa" => "fhfa.gov"}
  @source_ids ["qcew", "bea", "fhfa"]
  @panel_columns [
    "forecast_origin",
    "state_fips",
    "target_quarter",
    "target_quarter_number",
    "census_division",
    "evaluation_origin",
    "qcew_employment_yoy",
    "qcew_employment_qoq",
    "qcew_employment_yoy_lag1",
    "qcew_establishments_yoy",
    "qcew_total_wages_yoy",
    "bea_real_gdp_yoy",
    "bea_real_gdp_qoq",
    "bea_personal_income_yoy",
    "bea_personal_income_qoq",
    "fhfa_hpi_qoq",
    "fhfa_hpi_yoy",
    "qcew_release_date",
    "bea_release_date",
    "fhfa_release_date",
    "target_employment_growth_yoy",
    "outcome_available_date",
    "target_vintage"
  ]

  @doc "Loads the exact shared v1 contract."
  @spec load_contract(Path.t()) :: {:ok, map()} | {:error, term()}
  def load_contract(path \\ @contract_path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, contract} <- Jason.decode(bytes),
         "regional-expert-ensemble.v1" <- contract["schema_version"] do
      {:ok, contract}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_contract_schema, other}}
    end
  end

  @doc "Returns the SHA-256 of the exact committed contract bytes."
  @spec contract_sha256(Path.t()) :: String.t()
  def contract_sha256(path \\ @contract_path) do
    path |> File.read!() |> sha256()
  end

  @doc "Adds calendar quarters to a canonical YYYYQn identifier."
  @spec quarter_add(String.t(), integer()) :: String.t()
  def quarter_add(<<year::binary-size(4), "Q", quarter::binary-size(1)>>, amount)
      when quarter in ["1", "2", "3", "4"] and is_integer(amount) do
    serial = String.to_integer(year) * 4 + String.to_integer(quarter) - 1 + amount
    result_year = Integer.floor_div(serial, 4)
    result_quarter = Integer.mod(serial, 4) + 1
    "#{String.pad_leading(Integer.to_string(result_year), 4, "0")}Q#{result_quarter}"
  end

  def quarter_add(value, _amount), do: raise(ArgumentError, "invalid quarter: #{inspect(value)}")

  @doc "Returns the calendar quarter-end date."
  @spec quarter_end(String.t()) :: Date.t()
  def quarter_end(<<year::binary-size(4), "Q", quarter::binary-size(1)>>) do
    year = String.to_integer(year)

    case quarter do
      "1" -> Date.new!(year, 3, 31)
      "2" -> Date.new!(year, 6, 30)
      "3" -> Date.new!(year, 9, 30)
      "4" -> Date.new!(year, 12, 31)
      _other -> raise ArgumentError, "invalid quarter"
    end
  end

  @doc "Computes 100 times the natural-log growth rate from positive levels."
  @spec log_growth!(number(), number()) :: float()
  def log_growth!(current, prior) when current > 0 and prior > 0 do
    100.0 * :math.log(current / prior)
  end

  def log_growth!(_current, _prior),
    do: raise(ArgumentError, "log growth requires positive levels")

  @doc "Validates publisher identity, cutoff, and exact local source bytes."
  @spec validate_receipts([map()]) :: :ok | {:error, String.t()}
  def validate_receipts(receipts) when is_list(receipts) do
    result =
      receipts
      |> Enum.with_index()
      |> Enum.reduce_while(MapSet.new(), fn {receipt, index}, sources ->
        case validate_receipt(receipt, index) do
          {:ok, source} -> {:cont, MapSet.put(sources, source)}
          {:error, _reason} = error -> {:halt, error}
        end
      end)

    case result do
      %MapSet{} = sources ->
        if sources == MapSet.new(Map.keys(@source_hosts)),
          do: :ok,
          else: {:error, "sources: receipts for qcew, bea, and fhfa are required"}

      error ->
        error
    end
  end

  def validate_receipts(_other), do: {:error, "sources: expected array"}

  defp validate_receipt(receipt, index) when is_map(receipt) do
    path = "sources[#{index}]"

    with {:ok, source} <- required_text(receipt, "source_id", path),
         {:ok, required_host} <- source_host(source, path),
         {:ok, publisher_url} <- required_text(receipt, "publisher_url", path),
         :ok <- validate_host(publisher_url, required_host, path),
         {:ok, release_text} <- required_text(receipt, "release_date", path),
         :ok <- validate_release_date(release_text, path),
         {:ok, _retrieved_at} <- required_text(receipt, "retrieved_at", path),
         {:ok, _media_type} <- required_text(receipt, "media_type", path),
         {:ok, _terms_url} <- required_text(receipt, "terms_url", path),
         {:ok, _vintage_status} <- required_text(receipt, "vintage_status", path),
         {:ok, expected_hash} <- required_text(receipt, "sha256", path),
         {:ok, expected_bytes} <- positive_integer(receipt, "byte_count", path),
         {:ok, cache_path} <- required_text(receipt, "cache_path", path),
         {:ok, bytes} <- read_cache(cache_path, path),
         :ok <- validate_byte_count(bytes, expected_bytes, path),
         :ok <- validate_hash(bytes, expected_hash, path) do
      {:ok, source}
    end
  end

  defp validate_receipt(_receipt, index), do: {:error, "sources[#{index}]: expected object"}

  defp source_host(source, path) do
    case Map.fetch(@source_hosts, source) do
      {:ok, host} -> {:ok, host}
      :error -> {:error, "#{path}.source_id: unsupported source #{inspect(source)}"}
    end
  end

  defp required_text(map, key, path) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, "#{path}.#{key}: expected nonempty string"}
    end
  end

  defp positive_integer(map, key, path) do
    case map[key] do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _other -> {:error, "#{path}.#{key}: expected positive integer"}
    end
  end

  defp validate_host(url, required_host, path) do
    case URI.parse(url).host do
      host when host == required_host ->
        :ok

      host when is_binary(host) ->
        if String.ends_with?(host, ".#{required_host}"),
          do: :ok,
          else: {:error, "#{path}.publisher_url: host must be #{required_host}"}

      _other ->
        {:error, "#{path}.publisher_url: host must be #{required_host}"}
    end
  end

  defp validate_release_date(value, path) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        if Date.compare(date, @research_cutoff) in [:lt, :eq],
          do: :ok,
          else: {:error, "#{path}.release_date: exceeds research cutoff"}

      {:error, _reason} ->
        {:error, "#{path}.release_date: expected ISO date"}
    end
  end

  defp read_cache(cache_path, path) do
    case File.read(cache_path) do
      {:ok, bytes} ->
        {:ok, bytes}

      {:error, reason} ->
        {:error, "#{path}.cache_path: unreadable: #{:file.format_error(reason)}"}
    end
  end

  defp validate_byte_count(bytes, expected, path) do
    if byte_size(bytes) == expected,
      do: :ok,
      else: {:error, "#{path}.byte_count: cache byte count mismatch"}
  end

  defp validate_hash(bytes, expected, path) do
    if sha256(bytes) == expected,
      do: :ok,
      else: {:error, "#{path}.sha256: cache hash mismatch"}
  end

  @doc "Validates the complete normalized source bundle and its 51-state/DC vintages."
  @spec validate_source_bundle(map()) :: :ok | {:error, String.t()}
  def validate_source_bundle(bundle) when is_map(bundle) do
    with {:ok, contract} <- load_contract(),
         :ok <-
           require_equal(bundle["schema_version"], "regional-source-bundle.v1", "schema_version"),
         :ok <- require_equal(bundle["contract_sha256"], contract_sha256(), "contract_sha256"),
         :ok <-
           require_equal(
             bundle["research_cutoff"],
             contract["research_cutoff"],
             "research_cutoff"
           ),
         :ok <- validate_receipts(bundle["sources"]),
         {:ok, observations} <- require_map(bundle["observations"], "observations"),
         states = MapSet.new(contract["population"]["state_fips"]),
         :ok <- validate_observation_set("qcew", observations["qcew"], states),
         :ok <- validate_observation_set("bea", observations["bea"], states),
         :ok <- validate_observation_set("fhfa", observations["fhfa"], states) do
      :ok
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def validate_source_bundle(_other), do: {:error, "source bundle: expected object"}

  defp require_equal(actual, expected, path) do
    if actual == expected, do: :ok, else: {:error, "#{path}: does not match contract"}
  end

  defp require_map(value, _path) when is_map(value), do: {:ok, value}
  defp require_map(_value, path), do: {:error, "#{path}: expected object"}

  defp validate_observation_set(source, rows, states) when is_list(rows) and rows != [] do
    result =
      rows
      |> Enum.with_index()
      |> Enum.reduce_while({MapSet.new(), %{}}, fn {row, index}, {seen, groups} ->
        case validate_observation(source, row, index, states) do
          {:ok, key, group, state} ->
            if MapSet.member?(seen, key) do
              {:halt, {:error, "observations.#{source}[#{index}]: duplicate vintage key"}}
            else
              updated_groups =
                Map.update(groups, group, MapSet.new([state]), &MapSet.put(&1, state))

              {:cont, {MapSet.put(seen, key), updated_groups}}
            end

          {:error, _reason} = error ->
            {:halt, error}
        end
      end)

    case result do
      {%MapSet{}, groups} ->
        case Enum.find(groups, fn {_group, group_states} -> group_states != states end) do
          nil ->
            :ok

          {group, _group_states} ->
            {:error, "observations.#{source}: incomplete 51-state/DC vintage #{inspect(group)}"}
        end

      error ->
        error
    end
  end

  defp validate_observation_set(source, _rows, _states),
    do: {:error, "observations.#{source}: expected nonempty array"}

  defp validate_observation(source, row, index, states) when is_map(row) do
    path = "observations.#{source}[#{index}]"

    with {:ok, state} <- required_text(row, "state_fips", path),
         :ok <- require_state(state, states, path),
         {:ok, quarter} <- required_text(row, "observation_quarter", path),
         :ok <- validate_quarter(quarter, path),
         {:ok, release} <- required_text(row, "release_date", path),
         :ok <- validate_observation_release(release, path),
         :ok <- validate_observation_numbers(source, row, path),
         {:ok, discriminator} <- observation_discriminator(source, row, path) do
      {:ok, {state, quarter, release, discriminator}, {quarter, release, discriminator}, state}
    end
  end

  defp validate_observation(source, _row, index, _states),
    do: {:error, "observations.#{source}[#{index}]: expected object"}

  defp require_state(state, states, path) do
    if MapSet.member?(states, state),
      do: :ok,
      else: {:error, "#{path}.state_fips: outside state/DC universe"}
  end

  defp validate_quarter(quarter, path) do
    quarter_end(quarter)
    :ok
  rescue
    ArgumentError -> {:error, "#{path}.observation_quarter: invalid quarter"}
  end

  defp validate_observation_release(release, path) do
    case Date.from_iso8601(release) do
      {:ok, date} ->
        if Date.compare(date, @research_cutoff) in [:lt, :eq],
          do: :ok,
          else: {:error, "#{path}.release_date: exceeds research cutoff"}

      {:error, _reason} ->
        {:error, "#{path}.release_date: expected ISO date"}
    end
  end

  defp validate_observation_numbers(source, row, path) do
    fields =
      case source do
        "qcew" -> ["employment", "establishments", "total_wages"]
        "bea" -> ["real_gdp", "personal_income"]
        "fhfa" -> ["hpi_qoq", "hpi_yoy"]
      end

    Enum.reduce_while(fields, :ok, fn field, :ok ->
      value = row[field]

      cond do
        not is_number(value) ->
          {:halt, {:error, "#{path}.#{field}: expected finite number"}}

        source != "fhfa" and value <= 0 ->
          {:halt, {:error, "#{path}.#{field}: expected positive level"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp observation_discriminator("qcew", row, path) do
    case row["status"] do
      status when status in ["preliminary", "final"] -> {:ok, status}
      _other -> {:error, "#{path}.status: expected preliminary or final"}
    end
  end

  defp observation_discriminator("bea", row, path), do: required_text(row, "vintage", path)
  defp observation_discriminator("fhfa", row, path), do: required_text(row, "report_url", path)

  @doc "Builds the independently derived point-in-time state-quarter panel."
  @spec build_panel(map()) :: {:ok, [map()]} | {:error, String.t()}
  def build_panel(bundle) do
    with :ok <- validate_source_bundle(bundle),
         {:ok, contract} <- load_contract() do
      observations = bundle["observations"]
      population = contract["population"]
      time = contract["time"]
      states = population["state_fips"]
      divisions = population["census_divisions"]

      grouped =
        Map.new(@source_ids, fn source ->
          {source, Enum.group_by(observations[source], & &1["state_fips"])}
        end)

      panel =
        for origin <- quarters(time["source_start"], time["last_forecast_origin"]),
            state <- states do
          build_panel_row(
            origin,
            state,
            divisions[state],
            grouped,
            time["first_forecast_origin"],
            time["last_forecast_origin"]
          )
        end

      {:ok, panel}
    end
  rescue
    error in [ArgumentError, KeyError] -> {:error, Exception.message(error)}
  end

  defp build_panel_row(origin, state, division, grouped, first_evaluation, last_evaluation) do
    origin_end = quarter_end(origin)
    target_quarter = quarter_add(origin, 1)
    qcew_rows = grouped["qcew"][state]
    bea_rows = grouped["bea"][state]
    fhfa_rows = grouped["fhfa"][state]
    qcew = as_of_snapshot(qcew_rows, origin_end)
    bea = as_of_snapshot(bea_rows, origin_end)
    fhfa = as_of_snapshot(fhfa_rows, origin_end)
    q_latest = latest_quarter(qcew, origin)
    b_latest = latest_quarter(bea, origin)
    h_latest = latest_quarter(fhfa, origin)
    q0 = fetch_quarter!(qcew, q_latest, "qcew", state, origin)
    q1 = fetch_quarter!(qcew, quarter_add(q_latest, -1), "qcew", state, origin)
    q4 = fetch_quarter!(qcew, quarter_add(q_latest, -4), "qcew", state, origin)
    q5 = fetch_quarter!(qcew, quarter_add(q_latest, -5), "qcew", state, origin)
    b0 = fetch_quarter!(bea, b_latest, "bea", state, origin)
    b1 = fetch_quarter!(bea, quarter_add(b_latest, -1), "bea", state, origin)
    b4 = fetch_quarter!(bea, quarter_add(b_latest, -4), "bea", state, origin)
    h0 = fetch_quarter!(fhfa, h_latest, "fhfa", state, origin)
    target_current = final_qcew!(qcew_rows, target_quarter, state)
    target_prior = final_qcew!(qcew_rows, quarter_add(target_quarter, -4), state)

    row = %{
      "forecast_origin" => origin,
      "state_fips" => state,
      "target_quarter" => target_quarter,
      "target_quarter_number" => target_quarter |> String.last() |> String.to_integer(),
      "census_division" => division,
      "evaluation_origin" => origin >= first_evaluation and origin <= last_evaluation,
      "qcew_employment_yoy" => row_log_growth(q0, q4, "employment"),
      "qcew_employment_qoq" => row_log_growth(q0, q1, "employment"),
      "qcew_employment_yoy_lag1" => row_log_growth(q1, q5, "employment"),
      "qcew_establishments_yoy" => row_log_growth(q0, q4, "establishments"),
      "qcew_total_wages_yoy" => row_log_growth(q0, q4, "total_wages"),
      "bea_real_gdp_yoy" => row_log_growth(b0, b4, "real_gdp"),
      "bea_real_gdp_qoq" => row_log_growth(b0, b1, "real_gdp"),
      "bea_personal_income_yoy" => row_log_growth(b0, b4, "personal_income"),
      "bea_personal_income_qoq" => row_log_growth(b0, b1, "personal_income"),
      "fhfa_hpi_qoq" => h0["hpi_qoq"] * 1.0,
      "fhfa_hpi_yoy" => h0["hpi_yoy"] * 1.0,
      "qcew_release_date" => max_release([q0, q1, q4, q5]),
      "bea_release_date" => max_release([b0, b1, b4]),
      "fhfa_release_date" => h0["release_date"],
      "target_employment_growth_yoy" =>
        row_log_growth(target_current, target_prior, "employment"),
      "outcome_available_date" => max_release([target_current, target_prior]),
      "target_vintage" => target_current["vintage"]
    }

    Enum.each(@source_ids, fn source ->
      {:ok, release} = Date.from_iso8601(row["#{source}_release_date"])

      if Date.compare(release, origin_end) == :gt,
        do: raise(ArgumentError, "panel.#{origin}.#{state}.#{source}: post-origin feature")
    end)

    Map.take(row, @panel_columns)
  end

  defp quarters(first, last),
    do: Stream.iterate(first, &quarter_add(&1, 1)) |> Enum.take_while(&(&1 <= last))

  defp as_of_snapshot(rows, origin_end) do
    Enum.reduce(rows, %{}, fn row, selected ->
      {:ok, release} = Date.from_iso8601(row["release_date"])

      if Date.compare(release, origin_end) in [:lt, :eq] do
        Map.update(selected, row["observation_quarter"], row, fn prior ->
          if prior["release_date"] < row["release_date"], do: row, else: prior
        end)
      else
        selected
      end
    end)
  end

  defp latest_quarter(snapshot, origin) do
    snapshot
    |> Map.keys()
    |> Enum.filter(&(&1 <= origin))
    |> Enum.max(fn -> raise ArgumentError, "panel.#{origin}: no admitted source observation" end)
  end

  defp fetch_quarter!(snapshot, quarter, source, state, origin) do
    Map.fetch!(snapshot, quarter)
  rescue
    KeyError ->
      raise ArgumentError,
            "panel.#{origin}.#{state}.#{source}: missing required quarter #{quarter}"
  end

  defp final_qcew!(rows, quarter, state) do
    rows
    |> Enum.filter(&(&1["observation_quarter"] == quarter and &1["status"] == "final"))
    |> Enum.max_by(& &1["release_date"], fn ->
      raise ArgumentError, "target.#{quarter}.#{state}: missing final QCEW outcome"
    end)
  end

  defp row_log_growth(current, prior, field), do: log_growth!(current[field], prior[field])
  defp max_release(rows), do: rows |> Enum.map(& &1["release_date"]) |> Enum.max()

  @doc "Builds exact expanding fold membership with point-in-time outcome availability."
  @spec build_folds([map()]) :: [map()]
  def build_folds(panel) when is_list(panel) do
    {:ok, contract} = load_contract()
    minimum = contract["time"]["minimum_training_quarters"]

    panel
    |> Enum.filter(& &1["evaluation_origin"])
    |> Enum.map(& &1["forecast_origin"])
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn outer_origin ->
      outer_end = quarter_end(outer_origin)

      eligible =
        Enum.filter(panel, fn row ->
          row["forecast_origin"] < outer_origin and
            Date.compare(Date.from_iso8601!(row["outcome_available_date"]), outer_end) in [
              :lt,
              :eq
            ]
        end)

      if eligible |> Enum.map(& &1["forecast_origin"]) |> Enum.uniq() |> length() < minimum do
        []
      else
        train = Enum.map(eligible, &fold_row(&1, outer_origin, "train"))

        forecast =
          panel
          |> Enum.filter(&(&1["forecast_origin"] == outer_origin))
          |> Enum.map(&fold_row(&1, outer_origin, "forecast"))

        train ++ forecast
      end
    end)
    |> Enum.sort_by(fn row ->
      membership = if row["membership"] == "train", do: 0, else: 1
      {row["outer_origin"], membership, row["row_origin"], row["state_fips"]}
    end)
  end

  defp fold_row(row, outer_origin, membership) do
    %{
      "outer_origin" => outer_origin,
      "membership" => membership,
      "row_origin" => row["forecast_origin"],
      "state_fips" => row["state_fips"],
      "target_quarter" => row["target_quarter"],
      "outcome_available_date" => row["outcome_available_date"]
    }
  end

  @doc "Serializes canonical CSV with fixed column order and LF endings."
  @spec canonical_csv([map()], [String.t()]) :: String.t()
  def canonical_csv(rows, columns) when is_list(rows) and rows != [] and is_list(columns) do
    header = Enum.map_join(columns, ",", &csv_escape/1)

    body =
      Enum.map_join(rows, "\n", fn row ->
        Enum.map_join(columns, ",", fn column ->
          row |> Map.fetch!(column) |> canonical_value() |> csv_escape()
        end)
      end)

    header <> "\n" <> body <> "\n"
  end

  defp canonical_value(true), do: "true"
  defp canonical_value(false), do: "false"

  defp canonical_value(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 10)

  defp canonical_value(value), do: to_string(value)

  defp csv_escape(value) do
    value = to_string(value)

    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end

  @doc "Exhaustively searches four nonnegative 0.05 weights that sum to one."
  @spec search_convex_stack([[number()]], [number()]) :: [float()]
  def search_convex_stack(predictions, outcomes)
      when is_list(predictions) and predictions != [] and length(predictions) == length(outcomes) do
    candidates =
      for first <- 0..20,
          second <- 0..(20 - first),
          third <- 0..(20 - first - second) do
        fourth = 20 - first - second - third
        [first / 20.0, second / 20.0, third / 20.0, fourth / 20.0]
      end

    {weights, _mse} =
      Enum.reduce(candidates, {nil, :infinity}, fn weights, {best_weights, best_mse} ->
        mse = stack_mse(predictions, outcomes, weights)

        if best_weights == nil or mse < best_mse - 1.0e-15,
          do: {weights, mse},
          else: {best_weights, best_mse}
      end)

    weights
  end

  defp stack_mse(predictions, outcomes, weights) do
    predictions
    |> Enum.zip(outcomes)
    |> Enum.map(fn {row, outcome} ->
      prediction =
        row
        |> Enum.zip(weights)
        |> Enum.reduce(0.0, fn {value, weight}, sum -> sum + value * weight end)

      :math.pow(prediction - outcome, 2)
    end)
    |> then(&(Enum.sum(&1) / length(&1)))
  end

  @doc "Stable softmax used by the gate and structural verifier."
  @spec softmax([number()]) :: [float()]
  def softmax(values) when is_list(values) and values != [] do
    maximum = Enum.max(values)
    exponentials = Enum.map(values, &:math.exp(&1 - maximum))
    total = Enum.sum(exponentials)
    Enum.map(exponentials, &(&1 / total))
  end

  @doc "Builds the Axon tanh-to-softmax gate required by the v1 challenger."
  @spec neural_gate_model(pos_integer()) :: Axon.t()
  def neural_gate_model(input_width) when is_integer(input_width) and input_width > 0 do
    "gate_input"
    |> Axon.input(shape: {nil, input_width})
    |> Axon.dense(16, activation: :tanh, name: "gate_hidden")
    |> Axon.dense(4, activation: :softmax, name: "expert_weights")
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
