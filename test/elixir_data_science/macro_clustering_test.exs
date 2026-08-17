defmodule ElixirDataScience.MacroClusteringTest do
  use ExUnit.Case

  alias ElixirDataScience.{BLS, BLSFixture, Charts, MacroClustering}

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

  test "fits deterministic descriptive clusters and exposes dataframes", %{
    observations: observations
  } do
    assert {:ok, first} = MacroClustering.cluster(observations, num_clusters: 3, seed: 42)
    assert {:ok, second} = MacroClustering.cluster(observations, num_clusters: 3, seed: 42)

    assert Enum.map(first.observations, & &1.cluster) ==
             Enum.map(second.observations, & &1.cluster)

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
