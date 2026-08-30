defmodule ElixirDataScience.RegionalV2Test do
  use ExUnit.Case, async: true

  alias ElixirDataScience.RegionalV2
  alias ElixirDataScience.RegionalV2.PublishedObservation

  test "loads the shared v2 contract without changing v1" do
    assert {:ok, contract} = RegionalV2.load_contract()
    assert contract["schema_version"] == "regional-expert-ensemble.v2"

    assert RegionalV2.contract_sha256() ==
             "f318803c442f53f7fe43e0a730244beaf7729ef866cf670ed5dcb4f173baef1a"

    assert ElixirDataScience.RegionalExpertEnsemble.contract_sha256() ==
             "c1693dbe606629fcc1f63eb7a915f14219c7b2bc580ea85afc72371957f651c9"
  end

  test "derives the first complete QCEW feature origin from publication dates" do
    states = ["01", "02"]

    observations =
      for state <- states,
          {quarter, release_date} <- [
            {"2017Q1", ~D[2017-09-06]},
            {"2017Q2", ~D[2017-12-07]},
            {"2017Q3", ~D[2018-03-08]},
            {"2017Q4", ~D[2018-06-07]},
            {"2018Q1", ~D[2018-09-06]},
            {"2018Q2", ~D[2018-12-06]}
          ] do
        %PublishedObservation{
          source_id: :qcew,
          state_fips: state,
          observation_period: quarter,
          release_date: release_date,
          vintage: Date.to_iso8601(release_date),
          values: %{employment: 100.0}
        }
      end

    assert {:ok, "2018Q4"} =
             RegionalV2.first_complete_quarter_origin(
               observations,
               states,
               "2017Q1",
               "2020Q1",
               [0, 1, 4, 5]
             )

    assert {:error, {:incomplete_origin, "2017Q1"}} =
             RegionalV2.require_complete_quarter_origin(
               observations,
               states,
               "2017Q1",
               [0, 1, 4, 5]
             )
  end

  test "requires eight fully published label quarters before an outer forecast" do
    rows =
      for index <- 0..9 do
        origin = RegionalV2.quarter_add("2018Q4", index)

        %RegionalV2.PanelRow{
          forecast_origin: origin,
          state_fips: "01",
          target_quarter: RegionalV2.quarter_add(origin, 1),
          target_quarter_number: origin |> String.last() |> String.to_integer(),
          census_division: "east_south_central",
          evaluation_origin: true,
          features: %{},
          source_release_dates: %{},
          target: 1.0,
          outcome_available_date: RegionalV2.quarter_end(origin) |> Date.add(180),
          target_vintage: "final"
        }
      end

    assert {:ok, "2021Q1"} = RegionalV2.first_eligible_outer_origin(rows, 8)
  end

  test "indexed bundles reject absolute paths, traversal, and symlinks" do
    root = Path.join(System.tmp_dir!(), "regional-v2-paths-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "normalized"))
    data_path = Path.join(root, "normalized/qcew.csv")
    File.write!(data_path, "state_fips\n01\n")

    artifact = RegionalV2.artifact_receipt!(root, "normalized/qcew.csv", 1)
    assert :ok = RegionalV2.validate_artifact(root, artifact)

    assert {:error, {:unsafe_relative_path, "/tmp/qcew.csv"}} =
             RegionalV2.validate_artifact(root, %{artifact | path: "/tmp/qcew.csv"})

    assert {:error, {:unsafe_relative_path, "../qcew.csv"}} =
             RegionalV2.validate_artifact(root, %{artifact | path: "../qcew.csv"})

    link = Path.join(root, "normalized/qcew-link.csv")
    File.ln_s!(data_path, link)

    assert {:error, {:symlink_artifact, "normalized/qcew-link.csv"}} =
             RegionalV2.validate_artifact(root, %{artifact | path: "normalized/qcew-link.csv"})

    outside =
      Path.join(System.tmp_dir!(), "regional-v2-outside-#{System.unique_integer([:positive])}")

    File.mkdir_p!(outside)
    File.write!(Path.join(outside, "qcew.csv"), "state_fips\n01\n")
    File.ln_s!(outside, Path.join(root, "linked"))

    assert {:error, {:symlink_artifact, "linked/qcew.csv"}} =
             RegionalV2.validate_artifact(root, %{artifact | path: "linked/qcew.csv"})
  end

  test "profile admission is explicit and conditional profiles stay inactive" do
    assert {:ok, profile} = RegionalV2.profile("leading_signals")
    assert profile.active?

    assert profile.experts == [
             :labor,
             :qcew_business,
             :industry,
             :formation,
             :construction,
             :growth,
             :housing
           ]

    assert {:error, {:inactive_profile, "energy_prospective"}} =
             RegionalV2.profile("energy_prospective")
  end

  test "screened stack ranks by prior MAE and emits exact zero weights" do
    experts = [:labor, :qcew_business, :industry, :formation, :construction, :growth]

    maes = %{
      labor: 2.0,
      qcew_business: 1.0,
      industry: 1.0,
      formation: 3.0,
      construction: 0.5,
      growth: 4.0
    }

    predictions = [
      [1.0, 1.0, 1.0, 10.0, 1.0, 10.0],
      [2.0, 2.0, 2.0, 10.0, 2.0, 10.0],
      [3.0, 3.0, 3.0, 10.0, 3.0, 10.0]
    ]

    assert {:ok, result} =
             RegionalV2.screened_convex_stack(experts, maes, predictions, [1.0, 2.0, 3.0])

    assert result.selected_experts == [:construction, :qcew_business, :industry, :labor]
    assert Map.keys(result.weights) |> Enum.sort() == Enum.sort(experts)
    assert result.weights.formation == 0.0
    assert result.weights.growth == 0.0
    assert_in_delta Enum.sum(Map.values(result.weights)), 1.0, 1.0e-12
  end

  test "v2 neural model output width follows the active expert count" do
    model = RegionalV2.neural_gate_model(25, 7)
    assert %Axon{} = model

    output =
      Axon.get_output_shape(model, %{
        "gate_input" => Nx.template({1, 25}, {:f, 32})
      })

    assert Nx.shape(output) == {1, 7}
  end
end
