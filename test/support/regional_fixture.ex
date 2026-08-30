defmodule ElixirDataScience.RegionalFixture do
  @moduledoc false

  alias ElixirDataScience.RegionalExpertEnsemble, as: Regional

  @spec bundle(Path.t()) :: Regional.json_object()
  def bundle(root) do
    File.mkdir_p!(root)
    {:ok, contract} = Regional.load_contract()
    states = contract["population"]["state_fips"]

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

    {qcew, bea, fhfa} =
      quarters("2015Q1", "2025Q4")
      |> Enum.with_index()
      |> Enum.reduce({[], [], []}, fn {quarter, quarter_index}, {qcew, bea, fhfa} ->
        quarter_end = Regional.quarter_end(quarter)

        Enum.with_index(states)
        |> Enum.reduce({qcew, bea, fhfa}, fn {state, state_index}, {qcew, bea, fhfa} ->
          scale = 100_000.0 + state_index * 1_000.0
          trend = 1.0 + quarter_index * 0.008 + state_index * 0.0001

          qcew_rows =
            for {status, days, adjustment} <- [
                  {"preliminary", 75, 0.997},
                  {"final", 165, 1.0}
                ] do
              %{
                "state_fips" => state,
                "observation_quarter" => quarter,
                "release_date" => quarter_end |> Date.add(days) |> Date.to_iso8601(),
                "vintage" => "#{quarter}-#{status}",
                "status" => status,
                "employment" => scale * trend * adjustment,
                "establishments" => scale / 20.0 * (1.0 + quarter_index * 0.004) * adjustment,
                "total_wages" => scale * 2_000.0 * (1.0 + quarter_index * 0.012) * adjustment
              }
            end

          bea_row = %{
            "state_fips" => state,
            "observation_quarter" => quarter,
            "release_date" => quarter_end |> Date.add(80) |> Date.to_iso8601(),
            "vintage" => "bea-#{quarter}",
            "real_gdp" => scale * 10.0 * (1.0 + quarter_index * 0.01),
            "personal_income" => scale * 8.0 * (1.0 + quarter_index * 0.009)
          }

          fhfa_row = %{
            "state_fips" => state,
            "observation_quarter" => quarter,
            "release_date" => quarter_end |> Date.add(60) |> Date.to_iso8601(),
            "report_url" => "https://www.fhfa.gov/reports/house-price-index/#{quarter}",
            "hpi_qoq" => 0.5 + state_index * 0.001 + quarter_index * 0.002,
            "hpi_yoy" => 2.0 + state_index * 0.002 + quarter_index * 0.004
          }

          {Enum.reverse(qcew_rows, qcew), [bea_row | bea], [fhfa_row | fhfa]}
        end)
      end)

    fhfa_layout_checks =
      fhfa
      |> Enum.uniq_by(& &1["report_url"])
      |> Enum.sort_by(& &1["report_url"])
      |> Enum.map(fn row ->
        %{
          "report_url" => row["report_url"],
          "release_date" => row["release_date"],
          "layout_era" => "synthetic_v1",
          "pdftotext_version" => "pdftotext -layout synthetic 1.0",
          "row_count" => 51,
          "expected_headings" => true,
          "numeric_values" => true,
          "warning_text_preserved" => true,
          "manual_samples_verified" => true
        }
      end)

    %{
      "schema_version" => "regional-source-bundle.v1",
      "contract_sha256" => Regional.contract_sha256(),
      "research_cutoff" => "2026-08-29",
      "extraction_tools" => %{"pdftotext" => "pdftotext -layout synthetic 1.0"},
      "fhfa_layout_checks" => fhfa_layout_checks,
      "sources" => receipts,
      "observations" => %{
        "qcew" => Enum.reverse(qcew),
        "bea" => Enum.reverse(bea),
        "fhfa" => Enum.reverse(fhfa)
      }
    }
  end

  defp quarters(first, last) do
    Stream.iterate(first, &Regional.quarter_add(&1, 1)) |> Enum.take_while(&(&1 <= last))
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
