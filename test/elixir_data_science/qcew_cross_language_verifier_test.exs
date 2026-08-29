defmodule ElixirDataScience.QCEWCrossLanguageVerifierTest do
  use ExUnit.Case, async: true

  alias ElixirDataScience.QCEWCrossLanguageVerifier

  @canonical_csv """
  state_fips,county_rows,qtrly_estabs,month1_emplvl,month2_emplvl,month3_emplvl,total_qtrly_wages
  01,2,30,300,320,340,3000
  02,1,30,300,310,320,3000
  """

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "qcew-cross-language-verifier-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    elixir_manifest = manifest("elixir", @canonical_csv)
    python_manifest = manifest("python", @canonical_csv)

    paths = %{
      elixir_result: Path.join(root, "elixir/qcew-state-totals.v1.csv"),
      elixir_manifest: Path.join(root, "elixir/qcew-comparison-manifest.v1.json"),
      python_result: Path.join(root, "python/qcew-state-totals.v1.csv"),
      python_manifest: Path.join(root, "python/qcew-comparison-manifest.v1.json")
    }

    write_pair(paths.elixir_result, paths.elixir_manifest, @canonical_csv, elixir_manifest)
    write_pair(paths.python_result, paths.python_manifest, @canonical_csv, python_manifest)

    %{paths: paths, python_manifest: python_manifest}
  end

  test "accepts exact canonical bytes and source/result contracts", %{paths: paths} do
    assert {:ok, report} = verify(paths)
    assert report.status == :match
    assert report.mismatches == []
    assert report.source_sha256 == String.duplicate("a", 64)
    assert report.result_sha256 == sha256(@canonical_csv)
    assert report.row_count == 2

    formatted = QCEWCrossLanguageVerifier.format_report(report)
    assert formatted =~ "QCEW cross-language verification: MATCH"
    assert formatted =~ "Rows: 2"
  end

  test "reports source identity and fixed contract mutations at exact paths", %{
    paths: paths,
    python_manifest: python_manifest
  } do
    mutated =
      python_manifest
      |> put_in(["source", "sha256"], String.duplicate("b", 64))
      |> put_in(["contract", "filters", "own_code"], "5")

    write_manifest(paths.python_manifest, mutated)

    assert {:error, report} = verify(paths)
    mismatches = mismatches_by_path(report)

    assert mismatches["cross_language.source.sha256"] == %{
             expected: String.duplicate("a", 64),
             actual: String.duplicate("b", 64)
           }

    assert mismatches["python_manifest.contract.filters.own_code"] == %{
             expected: "0",
             actual: "5"
           }
  end

  test "reports an invalid Python manifest generation timestamp", %{
    paths: paths,
    python_manifest: python_manifest
  } do
    invalid_manifest = Map.put(python_manifest, "generated_at", "not-a-utc-timestamp")
    write_manifest(paths.python_manifest, invalid_manifest)

    assert {:error, report} = verify(paths)
    mismatches = mismatches_by_path(report)

    assert mismatches["python_manifest.generated_at"] == %{
             expected: "UTC ISO 8601 timestamp",
             actual: "not-a-utc-timestamp"
           }
  end

  test "detects a self-consistent Python result value mutation by state and column", %{
    paths: paths,
    python_manifest: python_manifest
  } do
    mutated_csv =
      String.replace(@canonical_csv, "01,2,30,300,320,340,3000", "01,2,30,300,320,340,3001")

    mutated_manifest =
      python_manifest
      |> put_in(["result", "sha256"], sha256(mutated_csv))
      |> put_in(["result", "byte_count"], byte_size(mutated_csv))
      |> put_in(["result", "totals", "total_qtrly_wages"], 6001)

    write_pair(paths.python_result, paths.python_manifest, mutated_csv, mutated_manifest)

    assert {:error, report} = verify(paths)
    mismatches = mismatches_by_path(report)

    assert mismatches[
             "cross_language.result.rows[state_fips=01].total_qtrly_wages"
           ] == %{expected: 3000, actual: 3001}

    assert mismatches["cross_language.result.totals.total_qtrly_wages"] == %{
             expected: 6000,
             actual: 6001
           }

    assert mismatches["cross_language.result.sha256"] == %{
             expected: sha256(@canonical_csv),
             actual: sha256(mutated_csv)
           }
  end

  test "detects stale Python manifest metadata independently of cross-language values", %{
    paths: paths
  } do
    mutated_csv =
      String.replace(
        @canonical_csv,
        "01,2,30,300,320,340,3000",
        "01,2,30,300,320,340,3002"
      )

    File.write!(paths.python_result, mutated_csv)

    assert {:error, report} = verify(paths)
    mismatches = mismatches_by_path(report)

    assert mismatches["python_manifest.result.sha256"] == %{
             expected: sha256(mutated_csv),
             actual: sha256(@canonical_csv)
           }
  end

  test "detects canonical row-order mutations even when manifest metadata is refreshed", %{
    paths: paths,
    python_manifest: python_manifest
  } do
    [header, first, second, ""] = String.split(@canonical_csv, "\n")
    reordered_csv = Enum.join([header, second, first, ""], "\n")

    reordered_manifest =
      python_manifest
      |> put_in(["result", "sha256"], sha256(reordered_csv))
      |> put_in(["result", "byte_count"], byte_size(reordered_csv))

    write_pair(paths.python_result, paths.python_manifest, reordered_csv, reordered_manifest)

    assert {:error, report} = verify(paths)
    mismatches = mismatches_by_path(report)

    assert mismatches["python_result.csv.state_fips_order"] == %{
             expected: ["01", "02"],
             actual: ["02", "01"]
           }

    assert mismatches["cross_language.result.state_fips_order"] == %{
             expected: ["01", "02"],
             actual: ["02", "01"]
           }
  end

  test "reports a missing state row after candidate metadata is made self-consistent", %{
    paths: paths,
    python_manifest: python_manifest
  } do
    [header, first | _rest] = String.split(@canonical_csv, "\n")
    missing_row_csv = Enum.join([header, first, ""], "\n")

    missing_row_manifest =
      python_manifest
      |> put_in(["result", "sha256"], sha256(missing_row_csv))
      |> put_in(["result", "byte_count"], byte_size(missing_row_csv))
      |> put_in(["result", "row_count"], 1)
      |> put_in(["result", "totals"], %{
        "county_rows" => 2,
        "month1_emplvl" => 300,
        "month2_emplvl" => 320,
        "month3_emplvl" => 340,
        "qtrly_estabs" => 30,
        "total_qtrly_wages" => 3000
      })

    write_pair(paths.python_result, paths.python_manifest, missing_row_csv, missing_row_manifest)

    assert {:error, report} = verify(paths)
    mismatches = mismatches_by_path(report)

    assert mismatches["cross_language.result.rows[state_fips=02]"] == %{
             expected: %{
               "state_fips" => "02",
               "county_rows" => 1,
               "qtrly_estabs" => 30,
               "month1_emplvl" => 300,
               "month2_emplvl" => 310,
               "month3_emplvl" => 320,
               "total_qtrly_wages" => 3000
             },
             actual: "<missing>"
           }

    assert mismatches["python_manifest.result.selected_row_count"] == %{
             expected: 2,
             actual: 3
           }
  end

  test "rejects a zero county count even when candidate totals are refreshed", %{
    paths: paths,
    python_manifest: python_manifest
  } do
    zero_count_csv = String.replace(@canonical_csv, "01,2,30", "01,0,30")

    zero_count_manifest =
      python_manifest
      |> put_in(["result", "sha256"], sha256(zero_count_csv))
      |> put_in(["result", "byte_count"], byte_size(zero_count_csv))
      |> put_in(["result", "totals", "county_rows"], 1)

    write_pair(
      paths.python_result,
      paths.python_manifest,
      zero_count_csv,
      zero_count_manifest
    )

    assert {:error, report} = verify(paths)
    mismatches = mismatches_by_path(report)

    assert mismatches["python_result.csv.rows[line=2].county_rows"] == %{
             expected: "positive canonical signed 64-bit integer",
             actual: "0"
           }
  end

  test "reports CRLF and value mutations even when candidate metadata is refreshed", %{
    paths: paths,
    python_manifest: python_manifest
  } do
    crlf_csv =
      @canonical_csv
      |> String.replace("01,2,30,300,320,340,3000", "01,2,30,300,320,340,3001")
      |> String.replace("\n", "\r\n")

    crlf_manifest =
      python_manifest
      |> put_in(["result", "sha256"], sha256(crlf_csv))
      |> put_in(["result", "byte_count"], byte_size(crlf_csv))
      |> put_in(["result", "totals", "total_qtrly_wages"], 6001)

    write_pair(paths.python_result, paths.python_manifest, crlf_csv, crlf_manifest)

    assert {:error, report} = verify(paths)
    mismatches = mismatches_by_path(report)

    assert mismatches["python_result.csv.line_ending"] == %{
             expected: "LF",
             actual: "contains CR bytes"
           }

    assert mismatches[
             "cross_language.result.rows[state_fips=01].total_qtrly_wages"
           ] == %{expected: 3000, actual: 3001}
  end

  test "reports final-newline and value mutations independently", %{
    paths: paths,
    python_manifest: python_manifest
  } do
    no_final_newline_csv =
      @canonical_csv
      |> String.replace("01,2,30,300,320,340,3000", "01,2,30,300,320,340,3001")
      |> String.trim_trailing("\n")

    no_final_newline_manifest =
      python_manifest
      |> put_in(["result", "sha256"], sha256(no_final_newline_csv))
      |> put_in(["result", "byte_count"], byte_size(no_final_newline_csv))
      |> put_in(["result", "totals", "total_qtrly_wages"], 6001)

    write_pair(
      paths.python_result,
      paths.python_manifest,
      no_final_newline_csv,
      no_final_newline_manifest
    )

    assert {:error, report} = verify(paths)
    mismatches = mismatches_by_path(report)

    assert mismatches["python_result.csv.final_newline"] == %{
             expected: true,
             actual: false
           }

    assert mismatches[
             "cross_language.result.rows[state_fips=01].total_qtrly_wages"
           ] == %{expected: 3000, actual: 3001}
  end

  test "rejects a result row count greater than the selected source rows", %{
    paths: paths,
    python_manifest: python_manifest
  } do
    invalid_manifest = put_in(python_manifest, ["result", "row_count"], 4)
    write_manifest(paths.python_manifest, invalid_manifest)

    assert {:error, report} = verify(paths)
    mismatches = mismatches_by_path(report)

    assert mismatches["python_manifest.result.row_count.bound"] == %{
             expected: "less than or equal to selected_row_count",
             actual: 4
           }
  end

  defp verify(paths) do
    QCEWCrossLanguageVerifier.verify(
      elixir_result_path: paths.elixir_result,
      elixir_manifest_path: paths.elixir_manifest,
      python_result_path: paths.python_result,
      python_manifest_path: paths.python_manifest
    )
  end

  defp manifest(runtime, csv) do
    runtime_metadata =
      case runtime do
        "elixir" -> %{"elixir" => "1.20.2", "otp" => "27"}
        "python" -> %{"python" => "3.14.0", "polars" => "1.32.3"}
      end

    %{
      "schema_version" => "qcew-comparison-manifest.v1",
      "experiment_id" => "qcew-2024-q1-county-total-by-state",
      "generated_at" => "2026-08-29T12:00:00Z",
      "source" => %{
        "schema_version" => "qcew-source-metadata.v1",
        "source_url" => "https://data.bls.gov/cew/data/api/2024/1/industry/10.csv",
        "retrieved_at" => "2026-08-29T11:00:00Z",
        "retrieval_date" => "2026-08-29",
        "sha256" => String.duplicate("a", 64),
        "byte_count" => 10_000,
        "publisher" => "U.S. Bureau of Labor Statistics",
        "dataset" => "Quarterly Census of Employment and Wages",
        "media_type" => "text/csv",
        "copyright_status" => "BLS-published material is public domain",
        "copyright_url" => "https://www.bls.gov/opub/copyright-information.htm",
        "terms_url" => "https://www.bls.gov/developers/termsOfService.htm",
        "permitted_use" =>
          "BLS public-domain material may be used without specific permission; cite BLS and preserve the retrieval date and BLS disclaimer",
        "bls_disclaimer" =>
          "BLS.gov cannot vouch for the data or analyses derived from these data after the data have been retrieved from BLS.gov."
      },
      "contract" => contract(),
      "result" => %{
        "path" => "qcew-state-totals.v1.csv",
        "sha256" => sha256(csv),
        "byte_count" => byte_size(csv),
        "source_row_count" => 5,
        "selected_row_count" => 3,
        "row_count" => 2,
        "totals" => totals()
      },
      "environment" => %{"runtime" => runtime_metadata},
      "claims" => %{
        "causal" => false,
        "predictive" => false,
        "recession" => false,
        "financial" => false,
        "interpretation" =>
          "The result is a deterministic engineering comparison artifact, not an economic conclusion."
      }
    }
  end

  defp contract do
    %{
      "year" => 2024,
      "quarter" => 1,
      "slice" => %{"kind" => "industry", "industry_code" => "10"},
      "filters" => %{
        "agglvl_code" => "70",
        "industry_code" => "10",
        "own_code" => "0",
        "size_code" => "0"
      },
      "disclosure_rule" => "fail if any selected row has a nonblank disclosure_code",
      "area_fips_rule" => "require one unique five-digit county area_fips per selected row",
      "grouping_key" => "first two characters of area_fips",
      "aggregations" => %{
        "county_rows" => "count selected rows",
        "month1_emplvl" => "integer sum",
        "month2_emplvl" => "integer sum",
        "month3_emplvl" => "integer sum",
        "qtrly_estabs" => "integer sum",
        "total_qtrly_wages" => "integer sum"
      },
      "output_columns" => [
        "state_fips",
        "county_rows",
        "qtrly_estabs",
        "month1_emplvl",
        "month2_emplvl",
        "month3_emplvl",
        "total_qtrly_wages"
      ],
      "ordering" => ["state_fips ascending"],
      "csv" => %{
        "delimiter" => ",",
        "encoding" => "UTF-8",
        "header" => true,
        "line_ending" => "LF",
        "final_newline" => true
      }
    }
  end

  defp totals do
    %{
      "county_rows" => 3,
      "month1_emplvl" => 600,
      "month2_emplvl" => 630,
      "month3_emplvl" => 660,
      "qtrly_estabs" => 60,
      "total_qtrly_wages" => 6000
    }
  end

  defp write_pair(result_path, manifest_path, csv, manifest) do
    File.mkdir_p!(Path.dirname(result_path))
    File.write!(result_path, csv)
    write_manifest(manifest_path, manifest)
  end

  defp write_manifest(path, manifest) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(manifest, pretty: true) <> "\n")
  end

  defp mismatches_by_path(report) do
    Map.new(report.mismatches, fn mismatch ->
      {mismatch.path, %{expected: mismatch.expected, actual: mismatch.actual}}
    end)
  end

  defp sha256(value) do
    :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  end
end
