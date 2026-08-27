defmodule ElixirDataScience.QCEWComparisonTest do
  use ExUnit.Case, async: true

  alias ElixirDataScience.QCEWComparison

  @synthetic_qcew_csv """
  area_fips,own_code,industry_code,agglvl_code,size_code,year,qtr,disclosure_code,qtrly_estabs,month1_emplvl,month2_emplvl,month3_emplvl,total_qtrly_wages
  01001,0,10,70,0,2024,1,,10,100,110,120,1000
  01003,0,10,70,0,2024,1,,20,200,210,220,2000
  02013,0,10,70,0,2024,1,,30,300,310,320,3000
  01000,0,10,50,0,2024,1,,999,999,999,999,999
  01001,5,10,71,0,2024,1,,888,888,888,888,888
  """

  describe "configuration/0" do
    test "fixes the first-party source and cross-language grouping contract" do
      config = QCEWComparison.configuration()

      assert config.schema_version == "qcew-comparison-manifest.v1"

      assert config.source_url ==
               "https://data.bls.gov/cew/data/api/2024/1/industry/10.csv"

      assert config.year == 2024
      assert config.quarter == 1

      assert config.filters == %{
               "agglvl_code" => "70",
               "industry_code" => "10",
               "own_code" => "0",
               "size_code" => "0"
             }

      assert config.grouping_key == "first two characters of area_fips"
    end
  end

  describe "transform_csv/1" do
    test "filters county totals, groups integer measures by state FIPS, and emits canonical CSV" do
      assert {:ok, result} = QCEWComparison.transform_csv(@synthetic_qcew_csv)

      assert result.source_row_count == 5
      assert result.selected_row_count == 3
      assert result.output_row_count == 2

      assert result.csv ==
               "state_fips,county_rows,qtrly_estabs,month1_emplvl,month2_emplvl," <>
                 "month3_emplvl,total_qtrly_wages\n" <>
                 "01,2,30,300,320,340,3000\n" <>
                 "02,1,30,300,310,320,3000\n"

      assert result.sha256 == sha256(result.csv)

      assert result.totals == %{
               "county_rows" => 3,
               "month1_emplvl" => 600,
               "month2_emplvl" => 630,
               "month3_emplvl" => 660,
               "qtrly_estabs" => 60,
               "total_qtrly_wages" => 6000
             }
    end

    test "rejects a selected row whose source values are not disclosed" do
      csv =
        String.replace(
          @synthetic_qcew_csv,
          "02013,0,10,70,0,2024,1,,30",
          "02013,0,10,70,0,2024,1,N,30"
        )

      assert {:error, {:undisclosed_selected_rows, 1}} = QCEWComparison.transform_csv(csv)
    end

    test "rejects input that does not contain the documented QCEW fields" do
      assert {:error, {:invalid_qcew_csv, message}} =
               QCEWComparison.transform_csv("area_fips,year\n01001,2024\n")

      assert message =~ "own_code"
    end

    test "rejects malformed or duplicate selected county FIPS codes" do
      malformed = String.replace(@synthetic_qcew_csv, "02013,0,10,70", "2,0,10,70")

      assert {:error, {:invalid_selected_area_fips, ["2"]}} =
               QCEWComparison.transform_csv(malformed)

      duplicate =
        @synthetic_qcew_csv <>
          "01001,0,10,70,0,2024,1,,10,100,110,120,1000\n"

      assert {:error, {:duplicate_selected_area_fips, ["01001"]}} =
               QCEWComparison.transform_csv(duplicate)
    end

    test "is stable under row order changes and sensitive to source value changes" do
      [header | rows] = String.split(@synthetic_qcew_csv, "\n", trim: true)
      reordered = Enum.join([header | Enum.reverse(rows)], "\n") <> "\n"

      assert {:ok, original} = QCEWComparison.transform_csv(@synthetic_qcew_csv)
      assert {:ok, reordered_result} = QCEWComparison.transform_csv(reordered)
      assert reordered_result.csv == original.csv
      assert reordered_result.sha256 == original.sha256

      changed = String.replace(@synthetic_qcew_csv, ",120,1000\n", ",120,1001\n")

      assert {:ok, changed_result} = QCEWComparison.transform_csv(changed)
      assert changed_result.csv =~ "01,2,30,300,320,340,3001\n"
      refute changed_result.sha256 == original.sha256
    end

    test "rejects a missing selected measure" do
      missing = String.replace(@synthetic_qcew_csv, ",320,3000\n", ",320,\n")

      assert {:error, {:missing_selected_values, %{"total_qtrly_wages" => 1}}} =
               QCEWComparison.transform_csv(missing)
    end
  end

  describe "run/1" do
    test "keeps source bytes out of the manifest, pins hashes, and records repeated states" do
      root = Path.join(System.tmp_dir!(), "qcew-comparison-#{System.unique_integer([:positive])}")
      source_path = Path.join(root, "data/2024-q1-industry-10.csv")
      output_dir = Path.join(root, "artifacts")
      retrieved_at = ~U[2026-08-27 12:00:00Z]
      parent = self()

      download_fun = fn url, path ->
        send(parent, {:downloaded, url})
        File.write(path, @synthetic_qcew_csv)
      end

      memory_sample_fun = fn ->
        %{"beam_total_bytes" => 1_000, "rss_bytes" => 2_000}
      end

      environment_fun = fn ->
        %{
          "hardware" => %{
            "architecture" => "test-arch",
            "cpu_model" => "test-cpu",
            "logical_processors" => 4,
            "memory_total_bytes" => 8_000
          },
          "runtime" => %{"elixir" => "test-elixir", "otp" => "test-otp"}
        }
      end

      repository_fun = fn -> %{"commit" => "test-commit", "dirty" => false} end

      assert {:ok, execution} =
               QCEWComparison.run(
                 source_path: source_path,
                 output_dir: output_dir,
                 iterations: 3,
                 download_fun: download_fun,
                 now_fun: fn -> retrieved_at end,
                 memory_sample_fun: memory_sample_fun,
                 memory_sample_interval_ms: 1,
                 environment_fun: environment_fun,
                 repository_fun: repository_fun,
                 host_hardware_label: "test-host",
                 host_cpu_model: "test-host-cpu",
                 host_logical_processors: 8,
                 host_memory_bytes: 16_000
               )

      assert_received {:downloaded, "https://data.bls.gov/cew/data/api/2024/1/industry/10.csv"}

      assert File.read!(execution.result_path) ==
               QCEWComparison.transform_csv(@synthetic_qcew_csv) |> elem(1) |> Map.fetch!(:csv)

      manifest = execution.manifest_path |> File.read!() |> Jason.decode!()

      assert manifest["schema_version"] == "qcew-comparison-manifest.v1"
      assert manifest["source"]["retrieved_at"] == "2026-08-27T12:00:00Z"
      assert manifest["source"]["sha256"] == sha256(@synthetic_qcew_csv)
      assert manifest["source"]["cache_state"] == "downloaded_this_run"
      assert manifest["source"]["media_type"] == "text/csv"
      refute Map.has_key?(manifest["source"], "bytes")

      assert manifest["result"]["sha256"] == sha256(File.read!(execution.result_path))
      assert manifest["result"]["row_count"] == 2
      assert manifest["environment"]["hardware"]["cpu_model"] == "test-cpu"

      assert manifest["environment"]["host_hardware"] == %{
               "cpu_model" => "test-host-cpu",
               "label" => "test-host",
               "logical_processors" => 8,
               "memory_total_bytes" => 16_000,
               "metadata_source" => "operator_provided"
             }

      assert Enum.map(manifest["benchmark"]["measurements"], & &1["runtime_state"]) == [
               "cold_runtime",
               "warm_runtime",
               "warm_runtime"
             ]

      assert Enum.all?(manifest["benchmark"]["measurements"], fn measurement ->
               is_integer(measurement["elapsed_nanoseconds"]) and
                 measurement["elapsed_nanoseconds"] >= 0 and
                 measurement["peak_memory"]["rss_bytes"] == 2_000 and
                 measurement["peak_memory"]["beam_total_bytes"] == 1_000
             end)

      assert manifest["benchmark"]["filesystem_cache_state"] == "uncontrolled"

      assert manifest["benchmark"]["pre_iteration_cleanup"] ==
               "full BEAM garbage collection before each timed transform"

      assert manifest["claims"]["causal"] == false
      assert manifest["claims"]["predictive"] == false
      assert manifest["claims"]["financial"] == false

      assert {:ok, second_execution} =
               QCEWComparison.run(
                 source_path: source_path,
                 output_dir: Path.join(root, "artifacts-second"),
                 iterations: 2,
                 download_fun: fn _, _ -> flunk("verified local source should be reused") end,
                 now_fun: fn -> ~U[2030-01-01 00:00:00Z] end,
                 memory_sample_fun: memory_sample_fun,
                 environment_fun: environment_fun,
                 repository_fun: repository_fun
               )

      second_manifest = second_execution.manifest_path |> File.read!() |> Jason.decode!()
      assert second_manifest["source"]["cache_state"] == "reused_verified_local_file"
      assert second_manifest["source"]["retrieved_at"] == "2026-08-27T12:00:00Z"

      File.write!(source_path, @synthetic_qcew_csv <> "tampered")

      assert {:error, {:source_sha256_mismatch, expected, actual}} =
               QCEWComparison.run(
                 source_path: source_path,
                 output_dir: Path.join(root, "artifacts-tampered"),
                 iterations: 2
               )

      assert expected == sha256(@synthetic_qcew_csv)
      assert actual == sha256(@synthetic_qcew_csv <> "tampered")
    end

    test "refuses to refresh over a source file that has no owned metadata sidecar" do
      root = Path.join(System.tmp_dir!(), "qcew-unmanaged-#{System.unique_integer([:positive])}")
      source_path = Path.join(root, "important.csv")
      File.mkdir_p!(root)
      File.write!(source_path, "user-owned bytes")

      assert {:error, {:refuse_unmanaged_source_overwrite, ^source_path}} =
               QCEWComparison.run(
                 source_path: source_path,
                 output_dir: Path.join(root, "artifacts"),
                 iterations: 2,
                 refresh_source: true,
                 download_fun: fn _, _ -> flunk("unmanaged path must not be overwritten") end
               )

      assert File.read!(source_path) == "user-owned bytes"
    end

    test "rejects non-UTC retrieval metadata before publishing source files" do
      root = Path.join(System.tmp_dir!(), "qcew-time-#{System.unique_integer([:positive])}")
      source_path = Path.join(root, "source.csv")

      non_utc = %DateTime{
        year: 2026,
        month: 8,
        day: 27,
        hour: 12,
        minute: 0,
        second: 0,
        microsecond: {0, 0},
        time_zone: "Etc/GMT+5",
        zone_abbr: "-05",
        utc_offset: -18_000,
        std_offset: 0
      }

      assert {:error, {:invalid_retrieval_time, ^non_utc}} =
               QCEWComparison.run(
                 source_path: source_path,
                 output_dir: Path.join(root, "artifacts"),
                 iterations: 2,
                 now_fun: fn -> non_utc end,
                 download_fun: fn _, path -> File.write(path, @synthetic_qcew_csv) end
               )

      refute File.exists?(source_path)
      refute File.exists?(source_path <> ".source-metadata.v1.json")
    end

    test "rejects invalid optional host hardware counts before downloading" do
      assert {:error, {:invalid_host_logical_processors, 0}} =
               QCEWComparison.run(
                 source_path: "unused.csv",
                 output_dir: "unused-artifacts",
                 iterations: 2,
                 host_logical_processors: 0,
                 download_fun: fn _, _ -> flunk("invalid options must fail before download") end
               )

      assert {:error, {:invalid_host_memory_bytes, -1}} =
               QCEWComparison.run(
                 source_path: "unused.csv",
                 output_dir: "unused-artifacts",
                 iterations: 2,
                 host_memory_bytes: -1,
                 download_fun: fn _, _ -> flunk("invalid options must fail before download") end
               )
    end
  end

  defp sha256(value) do
    :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  end
end
