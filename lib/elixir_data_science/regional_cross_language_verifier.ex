defmodule ElixirDataScience.RegionalCrossLanguageVerifier do
  @moduledoc """
  No-write verifier for independently generated Elixir and Python v1 artifacts.
  """

  alias ElixirDataScience.RegionalExpertEnsemble, as: Regional

  @exact_files ["regional-panel.v1.csv", "regional-folds.v1.csv"]
  @prediction_file "regional-predictions.v1.csv"
  @manifest_file "regional-run-manifest.v1.json"
  @numeric_fields [
    "prediction",
    "final_outcome",
    "error",
    "interval_lower_80",
    "interval_upper_80",
    "alpha"
  ]
  @weight_fields ["weight_labor", "weight_business", "weight_growth", "weight_housing"]
  @contribution_fields [
    "contribution_labor",
    "contribution_business",
    "contribution_growth",
    "contribution_housing"
  ]
  @prediction_columns [
    "forecast_origin",
    "state_fips",
    "target_quarter",
    "census_division",
    "model_id",
    "prediction",
    "final_outcome",
    "error",
    "interval_lower_80",
    "interval_upper_80",
    "weight_labor",
    "weight_business",
    "weight_growth",
    "weight_housing",
    "contribution_labor",
    "contribution_business",
    "contribution_growth",
    "contribution_housing",
    "alpha"
  ]
  @categorical_fields [
    "forecast_origin",
    "state_fips",
    "target_quarter",
    "census_division",
    "model_id"
  ]
  @tolerance 1.0e-6

  @type mismatch :: %{path: String.t(), expected: term(), actual: term()}
  @type report :: %{
          status: :match | :mismatch | :invalid_input,
          tolerance: float(),
          mismatches: [mismatch()]
        }

  @spec verify(Path.t(), Path.t()) :: {:ok, report()} | {:error, report()}
  def verify(elixir_dir, python_dir) when is_binary(elixir_dir) and is_binary(python_dir) do
    mismatches =
      exact_file_mismatches(elixir_dir, python_dir) ++
        manifest_mismatches(elixir_dir, python_dir) ++
        prediction_mismatches(elixir_dir, python_dir)

    report = %{
      status: if(mismatches == [], do: :match, else: :mismatch),
      tolerance: @tolerance,
      mismatches: Enum.sort_by(Enum.uniq(mismatches), & &1.path)
    }

    if report.status == :match, do: {:ok, report}, else: {:error, report}
  rescue
    error in [File.Error, Jason.DecodeError, ArgumentError] ->
      {:error,
       %{
         status: :invalid_input,
         tolerance: @tolerance,
         mismatches: [
           %{path: "input", expected: "valid v1 artifacts", actual: Exception.message(error)}
         ]
       }}
  end

  @spec format_report(report()) :: String.t()
  def format_report(%{status: :match, tolerance: tolerance}) do
    "Regional cross-language verification: MATCH\nDeterministic tolerance: #{tolerance}"
  end

  def format_report(report) do
    details =
      Enum.map_join(report.mismatches, "\n", fn mismatch ->
        "- #{mismatch.path}\n  expected: #{inspect(mismatch.expected)}\n  actual: #{inspect(mismatch.actual)}"
      end)

    "Regional cross-language verification: MISMATCH (#{length(report.mismatches)})\n" <> details
  end

  defp exact_file_mismatches(elixir_dir, python_dir) do
    Enum.flat_map(@exact_files, fn file ->
      expected = File.read!(Path.join(elixir_dir, file))
      actual = File.read!(Path.join(python_dir, file))
      if expected == actual, do: [], else: [mismatch(file, sha256(expected), sha256(actual))]
    end)
  end

  defp manifest_mismatches(elixir_dir, python_dir) do
    {elixir_bytes, elixir} = read_manifest(elixir_dir)
    {python_bytes, python} = read_manifest(python_dir)
    contract_hash = Regional.contract_sha256()

    canonical_manifest_mismatches("elixir_manifest", elixir_bytes) ++
      canonical_manifest_mismatches("python_manifest", python_bytes) ++
      compare(
        "elixir_manifest.schema_version",
        "regional-run-manifest.v1",
        elixir["schema_version"]
      ) ++
      compare(
        "python_manifest.schema_version",
        "regional-run-manifest.v1",
        python["schema_version"]
      ) ++
      compare("elixir_manifest.contract_sha256", contract_hash, elixir["contract_sha256"]) ++
      compare("python_manifest.contract_sha256", contract_hash, python["contract_sha256"]) ++
      compare(
        "manifests.source_bundle_sha256",
        elixir["source_bundle_sha256"],
        python["source_bundle_sha256"]
      ) ++
      compare("manifests.settings", elixir["settings"], python["settings"]) ++
      compare("manifests.exclusions", elixir["exclusions"], python["exclusions"]) ++
      compare("manifests.claims", elixir["claims"], python["claims"]) ++
      recursive_compare("manifests.metrics", elixir["metrics"], python["metrics"]) ++
      manifest_structure_mismatches("elixir_manifest", elixir) ++
      manifest_structure_mismatches("python_manifest", python) ++
      artifact_hash_mismatches(elixir_dir, elixir, "elixir_manifest") ++
      artifact_hash_mismatches(python_dir, python, "python_manifest")
  end

  defp read_manifest(dir) do
    bytes = dir |> Path.join(@manifest_file) |> File.read!()
    {bytes, Jason.decode!(bytes)}
  end

  defp canonical_manifest_mismatches(prefix, bytes) do
    canonical? =
      String.ends_with?(bytes, "\n") and
        not String.ends_with?(bytes, "\n\n") and
        compact_json?(binary_part(bytes, 0, byte_size(bytes) - 1)) and
        canonical_object_order?(Jason.decode!(bytes, objects: :ordered_objects))

    if canonical?,
      do: [],
      else: [mismatch("#{prefix}.canonical_json", "sorted compact JSON with one final LF", bytes)]
  end

  defp compact_json?(bytes), do: compact_json?(bytes, false, false)
  defp compact_json?(<<>>, false, false), do: true
  defp compact_json?(<<>>, _in_string?, _escaped?), do: false

  defp compact_json?(<<_char, rest::binary>>, true, true),
    do: compact_json?(rest, true, false)

  defp compact_json?(<<?\\, rest::binary>>, true, false),
    do: compact_json?(rest, true, true)

  defp compact_json?(<<?\", rest::binary>>, true, false),
    do: compact_json?(rest, false, false)

  defp compact_json?(<<_char, rest::binary>>, true, false),
    do: compact_json?(rest, true, false)

  defp compact_json?(<<?\", rest::binary>>, false, false),
    do: compact_json?(rest, true, false)

  defp compact_json?(<<char, _rest::binary>>, false, false)
       when char in [32, 9, 10, 13],
       do: false

  defp compact_json?(<<_char, rest::binary>>, false, false),
    do: compact_json?(rest, false, false)

  defp canonical_object_order?(%Jason.OrderedObject{values: values}) do
    keys = Enum.map(values, &elem(&1, 0))

    keys == Enum.sort(keys) and keys == Enum.uniq(keys) and
      Enum.all?(values, fn {_key, value} -> canonical_object_order?(value) end)
  end

  defp canonical_object_order?(values) when is_list(values),
    do: Enum.all?(values, &canonical_object_order?/1)

  defp canonical_object_order?(_value), do: true

  defp manifest_structure_mismatches(prefix, manifest) do
    environment = manifest["environment"]
    git = manifest["git"]

    []
    |> require_map_field("#{prefix}.environment", environment)
    |> require_map_field("#{prefix}.git", git)
    |> Kernel.++(
      if is_map(environment) and is_binary(environment["implementation"]),
        do: [],
        else: [mismatch("#{prefix}.environment.implementation", "string", environment)]
    )
    |> Kernel.++(
      if is_map(git) and is_binary(git["head"]) and
           Regex.match?(~r/\A[0-9a-f]{40}\z/, git["head"]),
         do: [],
         else: [mismatch("#{prefix}.git.head", "40 lowercase hex characters", git)]
    )
    |> Kernel.++(
      if is_map(git) and is_boolean(git["dirty"]),
        do: [],
        else: [mismatch("#{prefix}.git.dirty", "boolean", git)]
    )
  end

  defp require_map_field(mismatches, _path, value) when is_map(value), do: mismatches

  defp require_map_field(mismatches, path, value),
    do: [mismatch(path, "object", value) | mismatches]

  defp artifact_hash_mismatches(dir, manifest, prefix) do
    (@exact_files ++ [@prediction_file])
    |> Enum.flat_map(fn file ->
      bytes = File.read!(Path.join(dir, file))
      artifact = get_in(manifest, ["artifacts", file]) || %{}

      compare("#{prefix}.artifacts.#{file}.sha256", sha256(bytes), artifact["sha256"]) ++
        compare(
          "#{prefix}.artifacts.#{file}.byte_count",
          byte_size(bytes),
          artifact["byte_count"]
        ) ++
        compare(
          "#{prefix}.artifacts.#{file}.row_count",
          csv_row_count(bytes),
          artifact["row_count"]
        )
    end)
  end

  defp csv_row_count(bytes), do: max(length(String.split(bytes, "\n", trim: true)) - 1, 0)

  defp prediction_mismatches(elixir_dir, python_dir) do
    {elixir_columns, elixir} = read_simple_csv(Path.join(elixir_dir, @prediction_file))
    {python_columns, python} = read_simple_csv(Path.join(python_dir, @prediction_file))
    elixir_keys = Map.keys(elixir) |> Enum.sort()
    python_keys = Map.keys(python) |> Enum.sort()

    compare("elixir_predictions.header", @prediction_columns, elixir_columns) ++
      compare("python_predictions.header", @prediction_columns, python_columns) ++
      compare("predictions.keys", elixir_keys, python_keys) ++
      Enum.flat_map(elixir_keys -- (elixir_keys -- python_keys), fn key ->
        compare_prediction(key, elixir[key], python[key])
      end)
  end

  defp compare_prediction(key, expected, actual) do
    prefix = "predictions.#{key}"

    categorical =
      Enum.flat_map(@categorical_fields, fn field ->
        compare("#{prefix}.#{field}", expected[field], actual[field])
      end)

    if expected["model_id"] == "neural_gate" do
      categorical ++
        numeric_compare(
          "#{prefix}.final_outcome",
          expected["final_outcome"],
          actual["final_outcome"]
        ) ++
        neural_mismatches("#{prefix}.elixir", expected) ++
        neural_mismatches("#{prefix}.python", actual)
    else
      weight_mismatches =
        if expected["model_id"] == "convex_stack" do
          Enum.flat_map(@weight_fields, &compare("#{prefix}.#{&1}", expected[&1], actual[&1]))
        else
          Enum.flat_map(
            @weight_fields,
            &numeric_compare("#{prefix}.#{&1}", expected[&1], actual[&1])
          )
        end

      categorical ++
        Enum.flat_map(
          @numeric_fields ++ @contribution_fields,
          &numeric_compare("#{prefix}.#{&1}", expected[&1], actual[&1])
        ) ++
        weight_mismatches ++
        deterministic_structure_mismatches("#{prefix}.elixir", expected) ++
        deterministic_structure_mismatches("#{prefix}.python", actual)
    end
  end

  defp neural_mismatches(prefix, row), do: weighted_structure_mismatches(prefix, row, true)

  defp weighted_structure_mismatches(prefix, row, require_blank_alpha?) do
    prediction = parse_float(row["prediction"])
    outcome = parse_float(row["final_outcome"])
    error = parse_float(row["error"])
    lower = parse_float(row["interval_lower_80"])
    upper = parse_float(row["interval_upper_80"])
    weights = Enum.map(@weight_fields, &parse_float(row[&1]))
    contributions = Enum.map(@contribution_fields, &parse_float(row[&1]))

    cond do
      prediction == :error ->
        [mismatch("#{prefix}.prediction", "finite", row["prediction"])]

      Enum.any?([outcome, error, lower, upper], &(&1 == :error)) ->
        [
          mismatch("#{prefix}.outcome_error_interval", "four finite values", [
            outcome,
            error,
            lower,
            upper
          ])
        ]

      abs(error - (prediction - outcome)) > @tolerance ->
        [mismatch("#{prefix}.error", prediction - outcome, error)]

      lower > prediction or upper < prediction or lower > upper ->
        [
          mismatch("#{prefix}.interval", "lower <= prediction <= upper", [
            lower,
            prediction,
            upper
          ])
        ]

      Enum.any?(weights, &(&1 == :error)) ->
        [mismatch("#{prefix}.weights", "four finite values", weights)]

      Enum.any?(weights, &(&1 < 0.0 or &1 > 1.0)) ->
        [mismatch("#{prefix}.weights", "values in [0,1]", weights)]

      abs(Enum.sum(weights) - 1.0) > @tolerance ->
        [mismatch("#{prefix}.weights.sum", 1.0, Enum.sum(weights))]

      Enum.any?(contributions, &(&1 == :error)) ->
        [mismatch("#{prefix}.contributions", "four finite values", contributions)]

      abs(Enum.sum(contributions) - prediction) > @tolerance ->
        [mismatch("#{prefix}.contributions.sum", prediction, Enum.sum(contributions))]

      require_blank_alpha? and row["alpha"] != "" ->
        [mismatch("#{prefix}.alpha", "blank", row["alpha"])]

      true ->
        []
    end
  end

  defp deterministic_structure_mismatches(prefix, row) do
    weighted_models = [
      "labor",
      "business",
      "growth",
      "housing",
      "equal_weight",
      "inverse_mae",
      "convex_stack"
    ]

    if row["model_id"] in weighted_models do
      weighted_structure_mismatches(prefix, row, false)
    else
      fields = @weight_fields ++ @contribution_fields

      Enum.flat_map(fields, fn field ->
        if row[field] == "", do: [], else: [mismatch("#{prefix}.#{field}", "blank", row[field])]
      end)
    end
  end

  defp read_simple_csv(path) do
    [header | lines] = path |> File.read!() |> String.split("\n", trim: true)
    columns = String.split(header, ",")

    rows =
      Map.new(lines, fn line ->
        values = String.split(line, ",", parts: length(columns))
        row = Enum.zip(columns, values) |> Map.new()
        key = Enum.map_join(["forecast_origin", "state_fips", "model_id"], "/", &row[&1])
        {key, row}
      end)

    {columns, rows}
  end

  defp numeric_compare(path, expected, actual) do
    case {parse_float(expected), parse_float(actual)} do
      {:error, :error} ->
        []

      {left, right} when is_float(left) and is_float(right) ->
        if abs(left - right) <= @tolerance, do: [], else: [mismatch(path, left, right)]

      pair ->
        [mismatch(path, expected, {actual, pair})]
    end
  end

  defp recursive_compare(path, expected, actual) when is_map(expected) and is_map(actual) do
    expected_keys = Map.keys(expected) |> Enum.sort()
    actual_keys = Map.keys(actual) |> Enum.sort()

    compare("#{path}.keys", expected_keys, actual_keys) ++
      Enum.flat_map(expected_keys -- (expected_keys -- actual_keys), fn key ->
        recursive_compare("#{path}.#{key}", expected[key], actual[key])
      end)
  end

  defp recursive_compare(path, expected, actual)
       when is_list(expected) and is_list(actual) do
    compare("#{path}.length", length(expected), length(actual)) ++
      (expected
       |> Enum.zip(actual)
       |> Enum.with_index()
       |> Enum.flat_map(fn {{left, right}, index} ->
         recursive_compare("#{path}[#{index}]", left, right)
       end))
  end

  defp recursive_compare(path, expected, actual)
       when is_number(expected) and is_number(actual) and
              is_binary(path) do
    if String.contains?(path, ".neural_gate.") do
      if String.ends_with?(path, ".row_count"),
        do: compare(path, expected, actual),
        else: []
    else
      if abs(expected - actual) <= @tolerance,
        do: [],
        else: [mismatch(path, expected, actual)]
    end
  end

  defp recursive_compare(path, expected, actual)
       when is_number(expected) and is_number(actual) do
    if abs(expected - actual) <= @tolerance,
      do: [],
      else: [mismatch(path, expected, actual)]
  end

  defp recursive_compare(path, expected, actual), do: compare(path, expected, actual)

  defp parse_float(""), do: :error

  defp parse_float(value) do
    case Float.parse(value) do
      {number, ""} when number == number -> number
      _other -> :error
    end
  end

  defp compare(_path, expected, actual) when expected == actual, do: []
  defp compare(path, expected, actual), do: [mismatch(path, expected, actual)]
  defp mismatch(path, expected, actual), do: %{path: path, expected: expected, actual: actual}
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
