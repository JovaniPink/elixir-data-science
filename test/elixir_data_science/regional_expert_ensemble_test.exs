defmodule ElixirDataScience.RegionalExpertEnsembleTest do
  use ExUnit.Case, async: true

  alias ElixirDataScience.RegionalExpertEnsemble, as: Regional
  alias ElixirDataScience.RegionalFixture
  alias ElixirDataScience.RegionalModeling
  alias ElixirDataScience.RegionalSourceBuilder

  test "loads the committed contract and fixes its hash" do
    assert {:ok, contract} = Regional.load_contract()
    assert contract["schema_version"] == "regional-expert-ensemble.v1"
    assert length(contract["population"]["state_fips"]) == 51

    assert Regional.contract_sha256() ==
             "c1693dbe606629fcc1f63eb7a915f14219c7b2bc580ea85afc72371957f651c9"
  end

  test "quarter arithmetic and target formula are calendar based" do
    assert Regional.quarter_add("2020Q4", 1) == "2021Q1"
    assert Regional.quarter_add("2020Q1", -1) == "2019Q4"
    assert Regional.quarter_end("2024Q1") == ~D[2024-03-31]
    assert_in_delta Regional.log_growth!(108.0, 100.0), 7.696104113, 1.0e-9
    assert_raise ArgumentError, ~r/positive/, fn -> Regional.log_growth!(0.0, 100.0) end
  end

  test "convex stack searches the 0.05 simplex and uses the fixed tie break" do
    predictions = [[1.0, 1.0, 2.0, 2.0], [2.0, 2.0, 3.0, 3.0], [3.0, 3.0, 4.0, 4.0]]
    assert Regional.search_convex_stack(predictions, [1.0, 2.0, 3.0]) == [0.0, 1.0, 0.0, 0.0]
  end

  test "softmax weights are finite, bounded, and sum to one" do
    weights = Regional.softmax([2.0, -1.0, 0.5, 3.0])
    assert Enum.all?(weights, &(&1 >= 0.0 and &1 <= 1.0))
    assert_in_delta Enum.sum(weights), 1.0, 1.0e-12
  end

  test "canonical CSV uses fixed floats, lowercase booleans, and LF" do
    rows = [
      %{"forecast_origin" => "2020Q1", "state_fips" => "01", "value" => 1.5, "flag" => true}
    ]

    assert Regional.canonical_csv(rows, ["forecast_origin", "state_fips", "value", "flag"]) ==
             "forecast_origin,state_fips,value,flag\n2020Q1,01,1.5000000000,true\n"
  end

  test "canonical JSON sorts nested keys and uses one LF" do
    assert Regional.canonical_json(%{"z" => 1, "a" => %{"y" => true, "b" => 2}}) ==
             "{\"a\":{\"b\":2,\"y\":true},\"z\":1}\n"
  end

  test "source receipts reject a wrong publisher host and hash" do
    root = Path.join(System.tmp_dir!(), "regional-receipt-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    receipts =
      for {source, host} <- [{"qcew", "bls.gov"}, {"bea", "bea.gov"}, {"fhfa", "fhfa.gov"}] do
        bytes = "synthetic-#{source}\n"
        path = Path.join(root, "#{source}.source")
        File.write!(path, bytes)

        %{
          "source_id" => source,
          "publisher_url" => "https://www.#{host}/synthetic/#{source}",
          "release_date" => "2026-08-01",
          "retrieved_at" => "2026-08-29T12:00:00Z",
          "media_type" => if(source == "fhfa", do: "application/pdf", else: "text/csv"),
          "sha256" => sha256(bytes),
          "byte_count" => byte_size(bytes),
          "terms_url" => "https://www.#{host}/terms",
          "vintage_status" => "synthetic_test_fixture",
          "cache_path" => path
        }
      end

    assert :ok = Regional.validate_receipts(receipts)

    bad_host = put_in(receipts, [Access.at(0), "publisher_url"], "https://example.com/qcew")

    assert {:error, "sources[0].publisher_url: host must be bls.gov"} =
             Regional.validate_receipts(bad_host)

    bad_hash = put_in(receipts, [Access.at(1), "sha256"], String.duplicate("0", 64))

    assert {:error, "sources[1].sha256: cache hash mismatch"} =
             Regional.validate_receipts(bad_hash)
  end

  test "builds point-in-time panel and folds from the complete normalized bundle" do
    root = Path.join(System.tmp_dir!(), "regional-panel-#{System.unique_integer([:positive])}")
    bundle = RegionalFixture.bundle(root)

    assert :ok = Regional.validate_source_bundle(bundle)
    assert {:ok, panel} = Regional.build_panel(bundle)
    assert length(Enum.filter(panel, &(&1["forecast_origin"] == "2020Q1"))) == 51

    first = Enum.find(panel, &(&1["forecast_origin"] == "2020Q1" and &1["state_fips"] == "01"))
    assert first["target_quarter"] == "2020Q2"
    assert first["evaluation_origin"]

    assert Date.compare(Date.from_iso8601!(first["qcew_release_date"]), ~D[2020-03-31]) in [
             :lt,
             :eq
           ]

    assert first["outcome_available_date"] > "2020-06-30"

    folds = Regional.build_folds(panel)
    assert folds != []

    assert Enum.all?(folds, fn row ->
             row["membership"] == "forecast" or row["row_origin"] < row["outer_origin"]
           end)

    assert Enum.all?(folds, fn row ->
             row["membership"] == "forecast" or
               Date.compare(
                 Date.from_iso8601!(row["outcome_available_date"]),
                 Regional.quarter_end(row["outer_origin"])
               ) in [:lt, :eq]
           end)
  end

  test "rejects a future source observation before panel construction" do
    root = Path.join(System.tmp_dir!(), "regional-future-#{System.unique_integer([:positive])}")
    bundle = RegionalFixture.bundle(root)
    [first | rest] = bundle["observations"]["fhfa"]

    future =
      put_in(bundle, ["observations", "fhfa"], [%{first | "release_date" => "2027-01-01"} | rest])

    assert {:error, reason} = Regional.validate_source_bundle(future)
    assert reason =~ "research cutoff"
  end

  test "rejects FHFA layout evidence without preserved warning text" do
    root = Path.join(System.tmp_dir!(), "regional-layout-#{System.unique_integer([:positive])}")
    bundle = RegionalFixture.bundle(root)
    [first | rest] = bundle["fhfa_layout_checks"]

    invalid =
      put_in(bundle, ["fhfa_layout_checks"], [
        %{first | "warning_text_preserved" => false} | rest
      ])

    assert {:error, reason} = Regional.validate_source_bundle(invalid)
    assert reason =~ "warning_text_preserved"
  end

  test "trailing MAE never uses other states from the same quarter" do
    predictions = [[2.0, 4.0, 6.0, 8.0], [4.0, 6.0, 8.0, 10.0], [9.0, 9.0, 9.0, 9.0]]
    targets = [1.0, 3.0, 8.0]

    trailing =
      RegionalModeling.trailing_mae_matrix(
        predictions,
        targets,
        ["2020Q1", "2020Q1", "2020Q2"]
      )

    assert Enum.at(trailing, 0) == [1.0, 1.0, 1.0, 1.0]
    assert Enum.at(trailing, 1) == [1.0, 1.0, 1.0, 1.0]

    Enum.zip(Enum.at(trailing, 2), [1.0, 3.0, 5.0, 7.0])
    |> Enum.each(fn {actual, expected} -> assert_in_delta actual, expected, 1.0e-12 end)
  end

  test "source builder emits normalized artifacts and protects unmanaged refresh targets" do
    root = Path.join(System.tmp_dir!(), "regional-builder-#{System.unique_integer([:positive])}")
    bundle = RegionalFixture.bundle(Path.join(root, "source"))
    candidate = Path.join(root, "candidate.json")
    output = Path.join(root, "admitted")
    File.mkdir_p!(root)
    File.write!(candidate, Jason.encode!(bundle))

    assert {:ok, report} = RegionalSourceBuilder.build(candidate, output)
    assert report["source_count"] == 3
    assert File.exists?(Path.join(output, "regional-source-bundle.v1.json"))
    assert File.exists?(Path.join(output, "qcew-vintages.v1.csv"))
    assert File.exists?(Path.join(output, "bea-vintages.v1.csv"))
    assert File.exists?(Path.join(output, "fhfa-vintages.v1.csv"))

    download = fn url ->
      source =
        if String.contains?(url, "bls.gov"),
          do: "qcew",
          else: if(String.contains?(url, "bea.gov"), do: "bea", else: "fhfa")

      {:ok, "synthetic-#{source}\n"}
    end

    assert {:error, {:refuse_unmanaged_source_overwrite, path}} =
             RegionalSourceBuilder.build(candidate, Path.join(root, "refresh"),
               refresh_source: true,
               download_fun: download
             )

    assert path =~ ".source"
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
