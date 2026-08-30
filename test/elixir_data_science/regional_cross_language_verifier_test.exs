defmodule ElixirDataScience.RegionalCrossLanguageVerifierTest do
  use ExUnit.Case, async: true

  alias ElixirDataScience.RegionalCrossLanguageVerifier, as: Verifier
  alias ElixirDataScience.RegionalExpertEnsemble, as: Regional

  @panel "forecast_origin,state_fips,value\n2020Q1,01,1.0000000000\n"
  @folds "outer_origin,membership,row_origin,state_fips\n2020Q1,forecast,2020Q1,01\n"
  @header "forecast_origin,state_fips,target_quarter,census_division,model_id,prediction,final_outcome,error,interval_lower_80,interval_upper_80,weight_labor,weight_business,weight_growth,weight_housing,contribution_labor,contribution_business,contribution_growth,contribution_housing,alpha\n"
  @ridge "2020Q1,01,2020Q2,east_south_central,pooled_ridge,1.0000000000,1.1000000000,-0.1000000000,0.8000000000,1.2000000000,,,,,,,,,1.0000000000\n"
  @neural "2020Q1,01,2020Q2,east_south_central,neural_gate,1.0000000000,1.1000000000,-0.1000000000,0.8000000000,1.2000000000,0.2500000000,0.2500000000,0.2500000000,0.2500000000,0.2500000000,0.2500000000,0.2500000000,0.2500000000,\n"
  @convex "2020Q1,01,2020Q2,east_south_central,convex_stack,1.0000000000,1.1000000000,-0.1000000000,0.8000000000,1.2000000000,0.2500000000,0.2500000000,0.2500000000,0.2500000000,0.2500000000,0.2500000000,0.2500000000,0.2500000000,\n"

  test "matches valid pairs and rejects deterministic and neural mutations" do
    root = Path.join(System.tmp_dir!(), "regional-verifier-#{System.unique_integer([:positive])}")
    elixir_dir = Path.join(root, "elixir")
    python_dir = Path.join(root, "python")
    write_artifacts(elixir_dir, @ridge <> @neural <> @convex)
    write_artifacts(python_dir, @ridge <> @neural <> @convex)
    assert {:ok, %{status: :match}} = Verifier.verify(elixir_dir, python_dir)

    changed = String.replace(@ridge, "1.0000000000,1.1000000000", "1.0100000000,1.1000000000")
    write_artifacts(python_dir, changed <> @neural <> @convex)
    assert {:error, report} = Verifier.verify(elixir_dir, python_dir)
    assert Enum.any?(report.mismatches, &(&1.path =~ ".prediction"))

    invalid_neural =
      String.replace(
        @neural,
        "0.2500000000,0.2500000000,0.2500000000,0.2500000000",
        "0.9000000000,0.9000000000,0.0000000000,0.0000000000"
      )

    write_artifacts(python_dir, @ridge <> invalid_neural <> @convex)
    assert {:error, report} = Verifier.verify(elixir_dir, python_dir)
    assert Enum.any?(report.mismatches, &(&1.path =~ ".weights"))

    invalid_convex =
      String.replace(
        @convex,
        "0.2500000000,0.2500000000,0.2500000000,0.2500000000",
        "0.9000000000,0.1000000000,0.1000000000,0.1000000000"
      )

    write_artifacts(elixir_dir, @ridge <> @neural <> invalid_convex)
    write_artifacts(python_dir, @ridge <> @neural <> invalid_convex)
    assert {:error, report} = Verifier.verify(elixir_dir, python_dir)
    assert Enum.any?(report.mismatches, &(&1.path =~ ".weights.sum"))

    write_artifacts(elixir_dir, @ridge <> @neural <> @convex)
    write_artifacts(python_dir, @ridge <> @neural <> @convex, 9.0)
    assert {:error, report} = Verifier.verify(elixir_dir, python_dir)
    assert Enum.any?(report.mismatches, &(&1.path =~ "manifests.metrics"))

    write_artifacts(python_dir, @ridge <> @neural <> @convex)
    manifest_path = Path.join(python_dir, "regional-run-manifest.v1.json")
    manifest = manifest_path |> File.read!() |> Jason.decode!()
    File.write!(manifest_path, Jason.encode!(manifest, pretty: true) <> "\n")
    assert {:error, report} = Verifier.verify(elixir_dir, python_dir)
    assert Enum.any?(report.mismatches, &(&1.path =~ "canonical_json"))
  end

  defp write_artifacts(dir, prediction_rows, metric_value \\ 1.0) do
    File.mkdir_p!(dir)
    predictions = @header <> prediction_rows

    files = %{
      "regional-panel.v1.csv" => @panel,
      "regional-folds.v1.csv" => @folds,
      "regional-predictions.v1.csv" => predictions
    }

    Enum.each(files, fn {name, bytes} -> File.write!(Path.join(dir, name), bytes) end)

    {:ok, contract} = Regional.load_contract()

    manifest = %{
      "schema_version" => "regional-run-manifest.v1",
      "contract_sha256" => Regional.contract_sha256(),
      "source_bundle_sha256" => String.duplicate("a", 64),
      "artifacts" =>
        Map.new(files, fn {name, bytes} ->
          row_count = max(length(String.split(bytes, "\n", trim: true)) - 1, 0)

          {name,
           %{
             "sha256" => sha256(bytes),
             "byte_count" => byte_size(bytes),
             "row_count" => row_count
           }}
        end),
      "environment" => %{"implementation" => "test"},
      "git" => %{"head" => String.duplicate("b", 40), "dirty" => false},
      "settings" => %{
        "ridge" => contract["ridge"],
        "stack" => contract["stack"],
        "neural_gate" => contract["neural_gate"],
        "intervals" => contract["intervals"]
      },
      "metrics" => %{"overall" => %{"pooled_ridge" => %{"mae" => metric_value}}},
      "exclusions" => contract["excluded_v1"],
      "claims" => contract["claims"]
    }

    File.write!(
      Path.join(dir, "regional-run-manifest.v1.json"),
      Regional.canonical_json(manifest)
    )
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
