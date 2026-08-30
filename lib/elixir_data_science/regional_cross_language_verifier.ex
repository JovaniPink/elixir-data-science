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
  @categorical_fields [
    "forecast_origin",
    "state_fips",
    "target_quarter",
    "census_division",
    "model_id"
  ]
  @tolerance 1.0e-6

  @spec verify(Path.t(), Path.t()) :: {:ok, map()} | {:error, map()}
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

  @spec format_report(map()) :: String.t()
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
    elixir = read_manifest(elixir_dir)
    python = read_manifest(python_dir)
    contract_hash = Regional.contract_sha256()

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
      artifact_hash_mismatches(elixir_dir, elixir, "elixir_manifest") ++
      artifact_hash_mismatches(python_dir, python, "python_manifest")
  end

  defp read_manifest(dir), do: dir |> Path.join(@manifest_file) |> File.read!() |> Jason.decode!()

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
        )
    end)
  end

  defp prediction_mismatches(elixir_dir, python_dir) do
    elixir = read_simple_csv(Path.join(elixir_dir, @prediction_file))
    python = read_simple_csv(Path.join(python_dir, @prediction_file))
    elixir_keys = Map.keys(elixir) |> Enum.sort()
    python_keys = Map.keys(python) |> Enum.sort()

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
      categorical ++ neural_mismatches(prefix, actual)
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
          @numeric_fields,
          &numeric_compare("#{prefix}.#{&1}", expected[&1], actual[&1])
        ) ++ weight_mismatches
    end
  end

  defp neural_mismatches(prefix, row) do
    prediction = parse_float(row["prediction"])
    weights = Enum.map(@weight_fields, &parse_float(row[&1]))

    cond do
      prediction == :error ->
        [mismatch("#{prefix}.prediction", "finite", row["prediction"])]

      Enum.any?(weights, &(&1 == :error)) ->
        [mismatch("#{prefix}.weights", "four finite values", weights)]

      Enum.any?(weights, &(&1 < 0.0 or &1 > 1.0)) ->
        [mismatch("#{prefix}.weights", "values in [0,1]", weights)]

      abs(Enum.sum(weights) - 1.0) > @tolerance ->
        [mismatch("#{prefix}.weights.sum", 1.0, Enum.sum(weights))]

      true ->
        []
    end
  end

  defp read_simple_csv(path) do
    [header | lines] = path |> File.read!() |> String.split("\n", trim: true)
    columns = String.split(header, ",")

    Map.new(lines, fn line ->
      values = String.split(line, ",", parts: length(columns))
      row = Enum.zip(columns, values) |> Map.new()
      key = Enum.map_join(["forecast_origin", "state_fips", "model_id"], "/", &row[&1])
      {key, row}
    end)
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
