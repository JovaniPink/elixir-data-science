defmodule ElixirDataScience.BLSConformanceReportTest do
  use ExUnit.Case

  alias ElixirDataScience.{
    BLS,
    BLSConformanceReport,
    BLSFixture,
    BLSMacroExperiment,
    MacroClustering
  }

  setup do
    config = BLSMacroExperiment.configuration()

    request_fun = fn payload ->
      {:ok,
       BLSFixture.response(
         String.to_integer(payload["startyear"]),
         String.to_integer(payload["endyear"])
       )}
    end

    {:ok, dataset} = BLS.fetch(config.start_year, config.end_year, request_fun: request_fun)
    dataset = with_value_conditions(dataset)
    observations = MacroClustering.observations(dataset)
    {:ok, analysis} = MacroClustering.cluster(observations, config.cluster_options)

    %{analysis: analysis, config: config, dataset: dataset, observations: observations}
  end

  test "publishes the portable comparison contract" do
    contract = BLSMacroExperiment.conformance_contract()

    assert contract.schema_version == "bls-macro-conformance.v1"

    assert Enum.map(contract.features, & &1.name) == [
             "inflation_yoy",
             "unemployment_rate"
           ]

    assert contract.standardization == %{
             degrees_of_freedom: 0,
             formula: "(value - population_mean) / population_standard_deviation",
             method: "population_z_score"
           }

    assert contract.value_handling.unavailable.policy ==
             "retain source metadata, exclude from alignment, and do not impute"

    assert contract.value_handling.preliminary.propagation_inputs == [
             "current_cpi",
             "cpi_12_month_lag",
             "current_unemployment"
           ]
  end

  test "builds a label-independent comparison report without available source values", %{
    analysis: analysis,
    config: config,
    dataset: dataset,
    observations: observations
  } do
    assert {:ok, report} = BLSConformanceReport.build(dataset, analysis, config)

    assert report["schema_version"] == "bls-macro-conformance.v1"
    assert report["producer"]["language"] == "Elixir"

    assert report["request"] == %{
             "anonymous" => true,
             "end_year" => 2026,
             "inclusive_year_bounds" => true,
             "series_ids" => ["CUUR0000SA0", "LNS14000000"],
             "start_year" => 2006,
             "windows" => [
               %{"end_year" => 2015, "start_year" => 2006},
               %{"end_year" => 2025, "start_year" => 2016},
               %{"end_year" => 2026, "start_year" => 2026}
             ]
           }

    assert report["alignment"]["observation_count"] == length(observations)
    assert report["alignment"]["first_month"] == "2007-01"
    assert report["alignment"]["last_month"] == "2026-12"
    assert "2025-10" not in report["alignment"]["months"]
    assert "2026-10" not in report["alignment"]["months"]

    assert report["value_handling"]["unavailable"]["source_value_count"] == 2

    assert Enum.map(
             report["value_handling"]["unavailable"]["source_values"],
             &Map.take(&1, ["month", "series_id"])
           ) == [
             %{"month" => "2025-10", "series_id" => "CUUR0000SA0"},
             %{"month" => "2025-10", "series_id" => "LNS14000000"}
           ]

    assert report["value_handling"]["preliminary"]["source_value_count"] == 3
    assert report["value_handling"]["preliminary"]["aligned_observation_count"] == 3

    assert report["value_handling"]["preliminary"]["aligned_months"] == [
             "2007-07",
             "2026-06",
             "2026-08"
           ]

    assert Enum.map(report["features"], & &1["name"]) == [
             "inflation_yoy",
             "unemployment_rate"
           ]

    assert report["standardization"]["degrees_of_freedom"] == 0

    assert report["clustering"]["settings"] == %{
             "algorithm" => "k_means",
             "initialization" => "k_means_plus_plus",
             "max_iterations" => 300,
             "num_clusters" => 3,
             "num_runs" => 20,
             "seed" => 42,
             "tolerance" => 1.0e-4
           }

    profiles = report["descriptive_output"]["profiles"]

    assert Enum.map(profiles, & &1["comparison_profile_id"]) == [
             "profile_1",
             "profile_2",
             "profile_3"
           ]

    assert Enum.map(profiles, & &1["mean_inflation_yoy"]) ==
             profiles |> Enum.map(& &1["mean_inflation_yoy"]) |> Enum.sort()

    assert profiles |> Enum.flat_map(& &1["assigned_months"]) |> Enum.sort() ==
             report["alignment"]["months"]

    encoded = BLSConformanceReport.encode!(report)
    assert Jason.decode!(encoded) == report
    refute encoded =~ "\"available_values\""
    refute encoded =~ "\"raw_response\""
  end

  test "rejects request metadata that does not match the fixed configuration", %{
    analysis: analysis,
    config: config,
    dataset: dataset
  } do
    mismatched_dataset = %{dataset | request_windows: [{2006, 2026}]}

    assert {:error, {:request_configuration_mismatch, details}} =
             BLSConformanceReport.build(mismatched_dataset, analysis, config)

    assert details.actual_windows == [{2006, 2026}]
    assert details.expected_windows == [{2006, 2015}, {2016, 2025}, {2026, 2026}]
  end

  test "rejects stale descriptive profiles", %{
    analysis: analysis,
    config: config,
    dataset: dataset
  } do
    [profile | remaining_profiles] = analysis.profiles

    stale_analysis = %{
      analysis
      | profiles: [%{profile | months: profile.months + 1} | remaining_profiles]
    }

    assert {:error, {:analysis_profile_mismatch, details}} =
             BLSConformanceReport.build(dataset, stale_analysis, config)

    assert details.actual_profiles != details.expected_profiles
  end

  test "rejects stale standardization summaries", %{
    analysis: analysis,
    config: config,
    dataset: dataset
  } do
    for {feature, field} <- [
          {:inflation_yoy, :mean},
          {:unemployment_rate, :std}
        ] do
      stale_analysis =
        update_in(analysis, [:standardization, feature, field], &(&1 + 1.0))

      assert {:error, {:analysis_standardization_mismatch, details}} =
               BLSConformanceReport.build(dataset, stale_analysis, config)

      assert details.actual == stale_analysis.standardization
      assert details.expected == analysis.standardization
    end
  end

  test "writes only to an explicitly generated ignored artifact", %{
    analysis: analysis,
    config: config,
    dataset: dataset
  } do
    assert {:ok, report} = BLSConformanceReport.build(dataset, analysis, config)

    output_path =
      Path.join(
        System.tmp_dir!(),
        "bls-conformance-#{System.unique_integer([:positive])}/report.json"
      )

    assert :ok = BLSConformanceReport.write(report, output_path)
    assert output_path |> File.read!() |> Jason.decode!() == report

    ignored_paths = File.read!(".gitignore") |> String.split()
    assert "/artifacts" in ignored_paths
  end

  defp with_value_conditions(dataset) do
    preliminary_months = %{
      "CUUR0000SA0" => MapSet.new([~D[2006-07-01], ~D[2026-06-01]]),
      "LNS14000000" => MapSet.new([~D[2026-08-01]])
    }

    series =
      Map.new(dataset.series, fn {series_id, points} ->
        points =
          points
          |> Enum.reject(&(&1.date == ~D[2025-10-01]))
          |> Enum.map(fn point ->
            if MapSet.member?(preliminary_months[series_id], point.date) do
              %{point | preliminary?: true}
            else
              point
            end
          end)

        {series_id, points}
      end)

    unavailable =
      Map.new(BLS.series_ids(), fn series_id ->
        {series_id,
         [
           %{
             date: ~D[2025-10-01],
             value: "-",
             footnotes: ["Data unavailable in the synthetic fixture."]
           }
         ]}
      end)

    %{dataset | series: series, unavailable: unavailable}
  end
end
