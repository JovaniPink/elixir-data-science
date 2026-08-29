defmodule ElixirDataScience.QCEWCrossLanguageVerifier do
  @moduledoc """
  Verifies independently produced QCEW canonical CSV and manifest pairs.

  The verifier reads an Elixir reference pair and a Python candidate pair. It
  validates each pair against the versioned source/result contract, checks each
  manifest against its CSV bytes, and reports every deterministic mismatch. It
  does not write a report or copy either generated artifact.
  """

  alias ElixirDataScience.QCEWComparison

  @source_identity_fields [
    "source_url",
    "retrieved_at",
    "retrieval_date",
    "sha256",
    "byte_count",
    "media_type"
  ]
  @result_metadata_fields ["source_row_count", "selected_row_count", "row_count", "totals"]
  @missing "<missing>"
  @not_present "<not present>"
  @signed_64_min -9_223_372_036_854_775_808
  @signed_64_max 9_223_372_036_854_775_807

  @type json_value ::
          nil
          | boolean()
          | number()
          | String.t()
          | [json_value()]
          | %{optional(String.t()) => json_value()}

  @type manifest :: %{required(String.t()) => json_value()}

  @type mismatch :: %{
          path: String.t(),
          expected: json_value(),
          actual: json_value()
        }

  @type mismatch_list :: [mismatch()]

  @type report :: %{
          status: :match | :mismatch,
          source_sha256: json_value(),
          result_sha256: String.t(),
          row_count: non_neg_integer(),
          mismatches: [mismatch()]
        }

  @type option_key ::
          :elixir_result_path
          | :elixir_manifest_path
          | :python_result_path
          | :python_manifest_path

  @type file_label ::
          :elixir_result | :elixir_manifest | :python_result | :python_manifest

  @type paths :: %{
          elixir_result_path: Path.t(),
          elixir_manifest_path: Path.t(),
          python_result_path: Path.t(),
          python_manifest_path: Path.t()
        }

  @type input_error ::
          {:invalid_verifier_path, option_key(), term()}
          | {:missing_verifier_option, option_key()}
          | {:qcew_verifier_file_error, file_label(), Path.t(), atom()}
          | {:qcew_verifier_manifest_error, file_label(), Path.t(), String.t()}

  @type inspected_row :: %{required(String.t()) => String.t() | integer()}

  @type inspected_csv :: %{
          sha256: String.t(),
          byte_count: non_neg_integer(),
          row_count: non_neg_integer(),
          totals: %{required(String.t()) => integer()},
          rows: %{optional(String.t()) => inspected_row()},
          order: [String.t()],
          semantic_complete?: boolean()
        }

  @type verify_option ::
          {:elixir_result_path, Path.t()}
          | {:elixir_manifest_path, Path.t()}
          | {:python_result_path, Path.t()}
          | {:python_manifest_path, Path.t()}

  @doc "Verifies one Elixir reference pair against one Python candidate pair."
  @spec verify([verify_option()]) :: {:ok, report()} | {:error, report() | input_error()}
  def verify(opts) when is_list(opts) do
    with {:ok, paths} <- required_paths(opts),
         {:ok, elixir_csv} <- read_file(paths.elixir_result_path, :elixir_result),
         {:ok, elixir_manifest} <- read_manifest(paths.elixir_manifest_path, :elixir_manifest),
         {:ok, python_csv} <- read_file(paths.python_result_path, :python_result),
         {:ok, python_manifest} <- read_manifest(paths.python_manifest_path, :python_manifest) do
      {elixir_result, elixir_csv_mismatches} = inspect_csv(elixir_csv, "elixir_result")
      {python_result, python_csv_mismatches} = inspect_csv(python_csv, "python_result")

      mismatches =
        fixed_manifest_mismatches(elixir_manifest, "elixir_manifest") ++
          fixed_manifest_mismatches(python_manifest, "python_manifest") ++
          runtime_mismatches(elixir_manifest, python_manifest) ++
          manifest_result_mismatches(
            elixir_manifest,
            elixir_result,
            "elixir_manifest"
          ) ++
          manifest_result_mismatches(
            python_manifest,
            python_result,
            "python_manifest"
          ) ++
          elixir_csv_mismatches ++
          python_csv_mismatches ++
          cross_language_mismatches(
            elixir_manifest,
            elixir_result,
            python_manifest,
            python_result
          )

      mismatches =
        mismatches
        |> Enum.uniq()
        |> Enum.sort_by(fn mismatch ->
          {mismatch.path, inspect(mismatch.expected), inspect(mismatch.actual)}
        end)

      report = %{
        status: if(mismatches == [], do: :match, else: :mismatch),
        source_sha256: nested_value(elixir_manifest, ["source", "sha256"]),
        result_sha256: elixir_result.sha256,
        row_count: elixir_result.row_count,
        mismatches: mismatches
      }

      if report.status == :match, do: {:ok, report}, else: {:error, report}
    end
  end

  @doc "Formats a verification report for deterministic command-line output."
  @spec format_report(report()) :: String.t()
  def format_report(%{status: :match} = report) do
    [
      "QCEW cross-language verification: MATCH",
      "Source SHA-256: #{report.source_sha256}",
      "Result SHA-256: #{report.result_sha256}",
      "Rows: #{report.row_count}"
    ]
    |> Enum.join("\n")
  end

  def format_report(%{status: :mismatch} = report) do
    details =
      Enum.map(report.mismatches, fn mismatch ->
        "- #{mismatch.path}\n" <>
          "  expected: #{format_value(mismatch.expected)}\n" <>
          "  actual: #{format_value(mismatch.actual)}"
      end)

    (["QCEW cross-language verification: MISMATCH (#{length(report.mismatches)})"] ++
       details)
    |> Enum.join("\n")
  end

  @spec required_paths(keyword()) :: {:ok, paths()} | {:error, input_error()}
  defp required_paths(opts) do
    keys = [
      :elixir_result_path,
      :elixir_manifest_path,
      :python_result_path,
      :python_manifest_path
    ]

    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, paths} ->
      case Keyword.fetch(opts, key) do
        {:ok, path} when is_binary(path) and byte_size(path) > 0 ->
          {:cont, {:ok, Map.put(paths, key, path)}}

        {:ok, value} ->
          {:halt, {:error, {:invalid_verifier_path, key, value}}}

        :error ->
          {:halt, {:error, {:missing_verifier_option, key}}}
      end
    end)
  end

  @spec read_file(Path.t(), file_label()) :: {:ok, binary()} | {:error, input_error()}
  defp read_file(path, label) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, {:qcew_verifier_file_error, label, path, reason}}
    end
  end

  @spec read_manifest(Path.t(), file_label()) :: {:ok, manifest()} | {:error, input_error()}
  defp read_manifest(path, label) do
    with {:ok, encoded} <- read_file(path, label),
         {:ok, manifest} <- Jason.decode(encoded),
         true <- is_map(manifest) do
      {:ok, manifest}
    else
      {:error, {:qcew_verifier_file_error, _, _, _} = reason} ->
        {:error, reason}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:qcew_verifier_manifest_error, label, path, Exception.message(error)}}

      false ->
        {:error, {:qcew_verifier_manifest_error, label, path, "root must be an object"}}
    end
  end

  @spec fixed_manifest_mismatches(manifest(), String.t()) :: mismatch_list()
  defp fixed_manifest_mismatches(manifest, prefix) do
    artifact_contract = QCEWComparison.artifact_contract()

    fixed_fields =
      artifact_contract
      |> Map.drop(["contract", "claims"])
      |> diff_subset(manifest, prefix)

    fixed_fields ++
      diff_exact(
        artifact_contract["contract"],
        manifest["contract"],
        "#{prefix}.contract"
      ) ++
      diff_exact(artifact_contract["claims"], manifest["claims"], "#{prefix}.claims") ++
      timestamp_mismatches("#{prefix}.generated_at", manifest["generated_at"]) ++
      manifest_source_mismatches(manifest, prefix)
  end

  @spec manifest_source_mismatches(manifest(), String.t()) :: mismatch_list()
  defp manifest_source_mismatches(manifest, prefix) do
    source = manifest["source"]

    if is_map(source) do
      digest_mismatches("#{prefix}.source.sha256", source["sha256"]) ++
        non_negative_integer_mismatches(
          "#{prefix}.source.byte_count",
          source["byte_count"],
          positive: true
        ) ++
        timestamp_mismatches("#{prefix}.source.retrieved_at", source["retrieved_at"]) ++
        retrieval_date_mismatches(source, prefix)
    else
      []
    end
  end

  @spec retrieval_date_mismatches(manifest(), String.t()) :: mismatch_list()
  defp retrieval_date_mismatches(source, prefix) do
    retrieved_at = source["retrieved_at"]
    retrieval_date = source["retrieval_date"]

    if is_binary(retrieved_at) and byte_size(retrieved_at) >= 10 do
      compare(
        "#{prefix}.source.retrieval_date",
        String.slice(retrieved_at, 0, 10),
        retrieval_date
      )
    else
      []
    end
  end

  @spec runtime_mismatches(manifest(), manifest()) :: mismatch_list()
  defp runtime_mismatches(elixir_manifest, python_manifest) do
    nonempty_string_mismatches(
      "elixir_manifest.environment.runtime.elixir",
      nested_value(elixir_manifest, ["environment", "runtime", "elixir"])
    ) ++
      nonempty_string_mismatches(
        "python_manifest.environment.runtime.python",
        nested_value(python_manifest, ["environment", "runtime", "python"])
      )
  end

  @spec manifest_result_mismatches(manifest(), inspected_csv(), String.t()) :: mismatch_list()
  defp manifest_result_mismatches(manifest, inspected, prefix) do
    result = manifest["result"]

    if is_map(result) do
      digest_mismatches("#{prefix}.result.sha256", result["sha256"]) ++
        compare("#{prefix}.result.sha256", inspected.sha256, result["sha256"]) ++
        non_negative_integer_mismatches(
          "#{prefix}.result.byte_count",
          result["byte_count"],
          positive: true
        ) ++
        compare("#{prefix}.result.byte_count", inspected.byte_count, result["byte_count"]) ++
        result_count_mismatches(result, prefix) ++
        result_content_mismatches(result, inspected, prefix)
    else
      []
    end
  end

  @spec result_count_mismatches(manifest(), String.t()) :: mismatch_list()
  defp result_count_mismatches(result, prefix) do
    count_mismatches =
      ["source_row_count", "selected_row_count", "row_count"]
      |> Enum.flat_map(fn field ->
        non_negative_integer_mismatches(
          "#{prefix}.result.#{field}",
          result[field],
          positive: true
        )
      end)

    selected_count_bound =
      if is_integer(result["source_row_count"]) and
           is_integer(result["selected_row_count"]) and
           result["selected_row_count"] > result["source_row_count"] do
        [
          mismatch(
            "#{prefix}.result.selected_row_count.bound",
            "less than or equal to source_row_count",
            result["selected_row_count"]
          )
        ]
      else
        []
      end

    row_count_bound =
      if is_integer(result["selected_row_count"]) and is_integer(result["row_count"]) and
           result["row_count"] > result["selected_row_count"] do
        [
          mismatch(
            "#{prefix}.result.row_count.bound",
            "less than or equal to selected_row_count",
            result["row_count"]
          )
        ]
      else
        []
      end

    count_mismatches ++ selected_count_bound ++ row_count_bound
  end

  @spec result_content_mismatches(manifest(), inspected_csv(), String.t()) :: mismatch_list()
  defp result_content_mismatches(result, %{semantic_complete?: true} = inspected, prefix) do
    compare("#{prefix}.result.row_count", inspected.row_count, result["row_count"]) ++
      compare(
        "#{prefix}.result.selected_row_count",
        inspected.totals["county_rows"],
        result["selected_row_count"]
      ) ++
      diff_exact(inspected.totals, result["totals"], "#{prefix}.result.totals")
  end

  defp result_content_mismatches(_result, _inspected, _prefix), do: []

  @spec inspect_csv(binary(), String.t()) :: {inspected_csv(), [mismatch()]}
  defp inspect_csv(csv, prefix) do
    base = %{
      sha256: sha256(csv),
      byte_count: byte_size(csv),
      row_count: 0,
      totals: Map.new(integer_columns(), &{&1, 0}),
      rows: %{},
      order: [],
      semantic_complete?: false
    }

    if String.valid?(csv) do
      inspect_valid_utf8_csv(csv, prefix, base)
    else
      {base, [mismatch("#{prefix}.csv.encoding", "UTF-8", "invalid UTF-8 bytes")]}
    end
  end

  @spec inspect_valid_utf8_csv(binary(), String.t(), inspected_csv()) ::
          {inspected_csv(), mismatch_list()}
  defp inspect_valid_utf8_csv(csv, prefix, base) do
    line_ending_mismatches =
      if String.contains?(csv, "\r"),
        do: [mismatch("#{prefix}.csv.line_ending", "LF", "contains CR bytes")],
        else: []

    final_newline_mismatches =
      if String.ends_with?(csv, "\n"),
        do: [],
        else: [mismatch("#{prefix}.csv.final_newline", true, false)]

    semantic_csv = String.replace(csv, "\r\n", "\n")
    lines = String.split(semantic_csv, "\n", trim: false)
    lines = if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines

    case lines do
      [] ->
        {base,
         line_ending_mismatches ++
           final_newline_mismatches ++
           [mismatch("#{prefix}.csv.header", output_columns(), @missing)]}

      [header_line | data_lines] ->
        header = String.split(header_line, ",", trim: false)
        header_mismatches = compare("#{prefix}.csv.header", output_columns(), header)
        unique_header? = Enum.uniq(header) == header
        parseable_header? = unique_header? and Enum.sort(header) == Enum.sort(output_columns())

        {parsed_rows, row_mismatches, rows_complete?} =
          parse_rows(data_lines, header, parseable_header?, prefix)

        order = Enum.map(parsed_rows, & &1["state_fips"])
        sorted_order = Enum.sort(order)

        order_mismatches =
          compare_value("#{prefix}.csv.state_fips_order", sorted_order, order) ++
            duplicate_state_mismatches(order, prefix)

        rows = Map.new(parsed_rows, &{&1["state_fips"], &1})

        semantic_complete? =
          parseable_header? and rows_complete? and duplicate_state_mismatches(order, prefix) == []

        inspected = %{
          base
          | row_count: length(parsed_rows),
            totals: totals(parsed_rows),
            rows: rows,
            order: order,
            semantic_complete?: semantic_complete?
        }

        {inspected,
         line_ending_mismatches ++
           final_newline_mismatches ++ header_mismatches ++ row_mismatches ++ order_mismatches}
    end
  end

  @spec parse_rows([String.t()], [String.t()], boolean(), String.t()) ::
          {[inspected_row()], mismatch_list(), boolean()}
  defp parse_rows(data_lines, header, true, prefix) do
    data_lines
    |> Enum.with_index(2)
    |> Enum.reduce({[], [], true}, fn {line, line_number}, {rows, mismatches, complete?} ->
      values = String.split(line, ",", trim: false)

      if length(values) == length(header) do
        row = Map.new(Enum.zip(header, values))
        {parsed_row, current_mismatches} = parse_row(row, line_number, prefix)

        if current_mismatches == [] do
          {[parsed_row | rows], mismatches, complete?}
        else
          {rows, mismatches ++ current_mismatches, false}
        end
      else
        current =
          mismatch(
            "#{prefix}.csv.rows[line=#{line_number}].column_count",
            length(header),
            length(values)
          )

        {rows, mismatches ++ [current], false}
      end
    end)
    |> then(fn {rows, mismatches, complete?} ->
      {Enum.reverse(rows), mismatches, complete?}
    end)
  end

  defp parse_rows(data_lines, _header, false, prefix) do
    mismatch =
      mismatch(
        "#{prefix}.csv.rows",
        "rows parseable under the exact canonical header",
        "header does not contain each required column exactly once"
      )

    {[], if(data_lines == [], do: [], else: [mismatch]), false}
  end

  @spec parse_row(%{optional(String.t()) => String.t()}, pos_integer(), String.t()) ::
          {inspected_row(), mismatch_list()}
  defp parse_row(row, line_number, prefix) do
    state_fips = row["state_fips"]

    state_mismatches =
      if is_binary(state_fips) and Regex.match?(~r/^\d{2}$/, state_fips),
        do: [],
        else: [
          mismatch("#{prefix}.csv.rows[line=#{line_number}].state_fips", "two digits", state_fips)
        ]

    {integers, integer_mismatches} =
      Enum.reduce(integer_columns(), {%{}, []}, fn column, {values, mismatches} ->
        value = row[column]

        case parse_canonical_integer(value) do
          {:ok, integer} ->
            {Map.put(values, column, integer), mismatches}

          :error ->
            current =
              mismatch(
                "#{prefix}.csv.rows[line=#{line_number}].#{column}",
                "canonical signed 64-bit integer",
                value
              )

            {values, mismatches ++ [current]}
        end
      end)

    county_count_mismatches =
      case integers["county_rows"] do
        count when is_integer(count) and count > 0 ->
          []

        count when is_integer(count) ->
          [
            mismatch(
              "#{prefix}.csv.rows[line=#{line_number}].county_rows",
              "positive canonical signed 64-bit integer",
              row["county_rows"]
            )
          ]

        _missing ->
          []
      end

    {Map.put(integers, "state_fips", state_fips),
     state_mismatches ++ integer_mismatches ++ county_count_mismatches}
  end

  @spec parse_canonical_integer(term()) :: {:ok, integer()} | :error
  defp parse_canonical_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""}
      when integer >= @signed_64_min and integer <= @signed_64_max ->
        if Integer.to_string(integer) == value, do: {:ok, integer}, else: :error

      _other ->
        :error
    end
  end

  defp parse_canonical_integer(_value), do: :error

  @spec duplicate_state_mismatches([String.t()], String.t()) :: mismatch_list()
  defp duplicate_state_mismatches(order, prefix) do
    order
    |> Enum.frequencies()
    |> Enum.filter(fn {_state, count} -> count > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {state, count} ->
      mismatch("#{prefix}.csv.rows[state_fips=#{state}].count", 1, count)
    end)
  end

  @spec totals([inspected_row()]) :: %{required(String.t()) => integer()}
  defp totals(rows) do
    Enum.reduce(rows, Map.new(integer_columns(), &{&1, 0}), fn row, totals ->
      Map.new(totals, fn {column, total} -> {column, total + row[column]} end)
    end)
  end

  @spec cross_language_mismatches(manifest(), inspected_csv(), manifest(), inspected_csv()) ::
          mismatch_list()
  defp cross_language_mismatches(
         elixir_manifest,
         elixir_result,
         python_manifest,
         python_result
       ) do
    source_mismatches =
      Enum.flat_map(@source_identity_fields, fn field ->
        compare(
          "cross_language.source.#{field}",
          nested_value(elixir_manifest, ["source", field]),
          nested_value(python_manifest, ["source", field])
        )
      end)

    result_metadata_mismatches =
      Enum.flat_map(@result_metadata_fields, fn field ->
        diff_exact(
          nested_value(elixir_manifest, ["result", field]),
          nested_value(python_manifest, ["result", field]),
          "cross_language.result.#{field}"
        )
      end)

    source_mismatches ++
      result_metadata_mismatches ++
      compare("cross_language.result.sha256", elixir_result.sha256, python_result.sha256) ++
      compare(
        "cross_language.result.byte_count",
        elixir_result.byte_count,
        python_result.byte_count
      ) ++
      compare_value(
        "cross_language.result.state_fips_order",
        elixir_result.order,
        python_result.order
      ) ++
      cross_row_mismatches(elixir_result, python_result)
  end

  @spec cross_row_mismatches(inspected_csv(), inspected_csv()) :: mismatch_list()
  defp cross_row_mismatches(
         %{semantic_complete?: true} = expected,
         %{semantic_complete?: true} = actual
       ) do
    states = (Map.keys(expected.rows) ++ Map.keys(actual.rows)) |> Enum.uniq() |> Enum.sort()

    Enum.flat_map(states, fn state ->
      expected_row = expected.rows[state]
      actual_row = actual.rows[state]
      path = "cross_language.result.rows[state_fips=#{state}]"

      cond do
        is_nil(expected_row) ->
          [mismatch(path, @not_present, actual_row)]

        is_nil(actual_row) ->
          [mismatch(path, expected_row, @missing)]

        true ->
          Enum.flat_map(integer_columns(), fn column ->
            compare("#{path}.#{column}", expected_row[column], actual_row[column])
          end)
      end
    end)
  end

  defp cross_row_mismatches(_expected, _actual), do: []

  @spec digest_mismatches(String.t(), json_value()) :: mismatch_list()
  defp digest_mismatches(path, value) do
    if is_binary(value) and Regex.match?(~r/^[0-9a-f]{64}$/, value),
      do: [],
      else: [mismatch("#{path}.format", "64 lowercase hexadecimal characters", value)]
  end

  @spec timestamp_mismatches(String.t(), json_value()) :: mismatch_list()
  defp timestamp_mismatches(path, value) do
    valid? =
      is_binary(value) and
        match?({:ok, %DateTime{}, 0}, DateTime.from_iso8601(value))

    if valid?, do: [], else: [mismatch(path, "UTC ISO 8601 timestamp", value)]
  end

  @spec non_negative_integer_mismatches(String.t(), json_value(), keyword(boolean())) ::
          mismatch_list()
  defp non_negative_integer_mismatches(path, value, opts) do
    positive? = Keyword.get(opts, :positive, false)
    valid? = is_integer(value) and if(positive?, do: value > 0, else: value >= 0)
    expected = if positive?, do: "positive integer", else: "non-negative integer"

    if valid?, do: [], else: [mismatch("#{path}.format", expected, value)]
  end

  @spec nonempty_string_mismatches(String.t(), json_value()) :: mismatch_list()
  defp nonempty_string_mismatches(path, value) do
    if is_binary(value) and String.trim(value) != "",
      do: [],
      else: [mismatch(path, "nonempty version string", value || @missing)]
  end

  @spec diff_subset(json_value(), json_value(), String.t()) :: mismatch_list()
  defp diff_subset(expected, actual, path) when is_map(expected) and is_map(actual) do
    expected
    |> Map.keys()
    |> Enum.sort()
    |> Enum.flat_map(fn key ->
      case Map.fetch(actual, key) do
        {:ok, actual_value} -> diff_subset(expected[key], actual_value, append_path(path, key))
        :error -> [mismatch(append_path(path, key), expected[key], @missing)]
      end
    end)
  end

  defp diff_subset(expected, actual, path), do: diff_exact(expected, actual, path)

  @spec diff_exact(json_value(), json_value(), String.t()) :: mismatch_list()
  defp diff_exact(expected, actual, path) when is_map(expected) and is_map(actual) do
    (Map.keys(expected) ++ Map.keys(actual))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn key ->
      case {Map.fetch(expected, key), Map.fetch(actual, key)} do
        {{:ok, expected_value}, {:ok, actual_value}} ->
          diff_exact(expected_value, actual_value, append_path(path, key))

        {{:ok, expected_value}, :error} ->
          [mismatch(append_path(path, key), expected_value, @missing)]

        {:error, {:ok, actual_value}} ->
          [mismatch(append_path(path, key), @not_present, actual_value)]
      end
    end)
  end

  defp diff_exact(expected, actual, path) when is_list(expected) and is_list(actual) do
    if length(expected) == length(actual) do
      expected
      |> Enum.zip(actual)
      |> Enum.with_index()
      |> Enum.flat_map(fn {{expected_value, actual_value}, index} ->
        diff_exact(expected_value, actual_value, "#{path}[#{index}]")
      end)
    else
      [mismatch(path, expected, actual)]
    end
  end

  defp diff_exact(expected, actual, path) do
    if expected === actual, do: [], else: [mismatch(path, expected, actual)]
  end

  @spec compare(String.t(), json_value(), json_value()) :: mismatch_list()
  defp compare(path, expected, actual), do: diff_exact(expected, actual, path)

  @spec compare_value(String.t(), json_value(), json_value()) :: mismatch_list()
  defp compare_value(path, expected, actual) do
    if expected === actual, do: [], else: [mismatch(path, expected, actual)]
  end

  @spec mismatch(String.t(), json_value(), json_value()) :: mismatch()
  defp mismatch(path, expected, actual) do
    %{path: path, expected: expected, actual: actual}
  end

  @spec append_path(String.t(), String.t()) :: String.t()
  defp append_path("", key), do: key
  defp append_path(path, key), do: "#{path}.#{key}"

  @spec output_columns() :: [String.t()]
  defp output_columns, do: QCEWComparison.configuration().output_columns

  @spec integer_columns() :: [String.t()]
  defp integer_columns, do: output_columns() -- ["state_fips"]

  @spec nested_value(json_value(), [String.t()]) :: json_value()
  defp nested_value(value, []), do: value

  defp nested_value(map, [key | rest]) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> nested_value(value, rest)
      :error -> @missing
    end
  end

  defp nested_value(_value, _path), do: @missing

  @spec sha256(binary()) :: String.t()
  defp sha256(value) do
    :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  end

  @spec format_value(json_value()) :: String.t()
  defp format_value(value) do
    inspect(value, limit: :infinity, printable_limit: :infinity, pretty: false)
  end
end
