defmodule ElixirDataScience.MacroClusteringTest do
  use ExUnit.Case

  alias ElixirDataScience.{BLS, BLSFixture, BLSMacroExperiment, Charts, MacroClustering}

  test "exposes the fixed typed experiment configuration" do
    assert BLSMacroExperiment.configuration() == %{
             start_year: 2006,
             end_year: 2026,
             cluster_options: [
               num_clusters: 3,
               seed: 42,
               num_runs: 20,
               init: :k_means_plus_plus,
               max_iterations: 300,
               tolerance: 1.0e-4
             ]
           }
  end

  setup do
    request_fun = fn payload ->
      {:ok,
       BLSFixture.response(
         String.to_integer(payload["startyear"]),
         String.to_integer(payload["endyear"])
       )}
    end

    {:ok, dataset} = BLS.fetch(2000, 2005, request_fun: request_fun)
    observations = MacroClustering.observations(dataset)
    %{observations: observations}
  end

  test "derives aligned year-over-year inflation observations", %{observations: observations} do
    assert length(observations) == 60
    assert hd(observations).date == ~D[2001-01-01]
    assert List.last(observations).date == ~D[2005-12-01]
    assert_in_delta hd(observations).inflation_yoy, 3.0416, 0.01
  end

  test "propagates preliminary flags from current, lagged, and unemployment values" do
    cpi_points = [
      %{date: ~D[2025-05-01], value: 100.0, preliminary?: false},
      %{date: ~D[2025-06-01], value: 101.0, preliminary?: true},
      %{date: ~D[2025-07-01], value: 102.0, preliminary?: false},
      %{date: ~D[2025-08-01], value: 103.0, preliminary?: false},
      %{date: ~D[2026-05-01], value: 104.0, preliminary?: true},
      %{date: ~D[2026-06-01], value: 105.0, preliminary?: false},
      %{date: ~D[2026-07-01], value: 106.0, preliminary?: false},
      %{date: ~D[2026-08-01], value: 107.0, preliminary?: false}
    ]

    unemployment_points = [
      %{date: ~D[2026-05-01], value: 4.0, preliminary?: false},
      %{date: ~D[2026-06-01], value: 4.1, preliminary?: false},
      %{date: ~D[2026-07-01], value: 4.2, preliminary?: true},
      %{date: ~D[2026-08-01], value: 4.3, preliminary?: false}
    ]

    observations =
      MacroClustering.observations(%{
        series: %{
          "CUUR0000SA0" => cpi_points,
          "LNS14000000" => unemployment_points
        }
      })

    assert Enum.map(observations, &{&1.date, &1.preliminary?}) == [
             {~D[2026-05-01], true},
             {~D[2026-06-01], true},
             {~D[2026-07-01], true},
             {~D[2026-08-01], false}
           ]
  end

  test "fits deterministic descriptive clusters and exposes dataframes", %{
    observations: observations
  } do
    assert {:ok, first} = MacroClustering.cluster(observations, num_clusters: 3, seed: 42)
    assert {:ok, second} = MacroClustering.cluster(observations, num_clusters: 3, seed: 42)

    assert Enum.map(first.observations, & &1.cluster) ==
             Enum.map(second.observations, & &1.cluster)

    assert first.num_clusters == 3
    assert first.init == :k_means_plus_plus
    assert first.max_iterations == 300
    assert first.tolerance == 1.0e-4
    assert length(first.profiles) == 3
    assert Enum.sum(Enum.map(first.profiles, & &1.months)) == length(observations)
    assert Explorer.DataFrame.n_rows(MacroClustering.to_dataframe(first)) == 60
    assert Explorer.DataFrame.n_rows(MacroClustering.profiles_dataframe(first)) == 3
  end

  test "builds Vega-Lite timeline and scatter specifications", %{observations: observations} do
    {:ok, analysis} = MacroClustering.cluster(observations, num_clusters: 3, seed: 42)

    timeline = analysis.observations |> Charts.timeline() |> VegaLite.to_spec()
    scatter = analysis.observations |> Charts.scatter() |> VegaLite.to_spec()

    assert length(timeline["vconcat"]) == 2
    assert scatter["mark"]["type"] == "point"
    assert scatter["encoding"]["color"]["field"] == "cluster"
  end

  test "orders cluster profile boundaries chronologically across years" do
    observations = [
      %{date: ~D[2025-09-01], inflation_yoy: 1.0, unemployment_rate: 8.0, preliminary?: false},
      %{date: ~D[2025-10-01], inflation_yoy: 1.1, unemployment_rate: 8.1, preliminary?: false},
      %{date: ~D[2025-11-01], inflation_yoy: 1.2, unemployment_rate: 8.2, preliminary?: false},
      %{date: ~D[2025-12-01], inflation_yoy: 8.0, unemployment_rate: 4.0, preliminary?: false},
      %{date: ~D[2026-01-01], inflation_yoy: 8.1, unemployment_rate: 4.1, preliminary?: false},
      %{date: ~D[2026-07-01], inflation_yoy: 8.2, unemployment_rate: 4.2, preliminary?: false}
    ]

    assert {:ok, analysis} =
             MacroClustering.cluster(observations, num_clusters: 2, seed: 42, num_runs: 5)

    high_inflation_profile = Enum.find(analysis.profiles, &(&1.mean_inflation_yoy > 5.0))

    assert high_inflation_profile.first_month == "2025-12-01"
    assert high_inflation_profile.last_month == "2026-07-01"
  end

  test "rejects a constant feature rather than dividing by zero" do
    observations =
      for month <- 1..4 do
        %{
          date: Date.new!(2025, month, 1),
          inflation_yoy: 2.0,
          unemployment_rate: 4.0,
          preliminary?: false
        }
      end

    assert {:error, :constant_feature} =
             MacroClustering.cluster(observations, num_clusters: 2)
  end
end
