defmodule ElixirDataScience.BLSTest do
  use ExUnit.Case, async: true

  alias ElixirDataScience.BLS
  alias ElixirDataScience.BLSFixture

  test "splits anonymous requests into inclusive ten-year windows" do
    assert BLS.year_windows(2006, 2025) == [{2006, 2015}, {2016, 2025}]
    assert BLS.year_windows(2006, 2026) == [{2006, 2015}, {2016, 2025}, {2026, 2026}]
    assert BLS.year_windows(2025, 2026) == [{2025, 2026}]
  end

  test "fetch merges, sorts, and records provenance without a registration key" do
    parent = self()

    request_fun = fn payload ->
      send(parent, {:payload, payload})

      {:ok,
       BLSFixture.response(
         String.to_integer(payload["startyear"]),
         String.to_integer(payload["endyear"])
       )}
    end

    assert {:ok, dataset} = BLS.fetch(2006, 2025, request_fun: request_fun)
    assert dataset.request_windows == [{2006, 2015}, {2016, 2025}]
    assert dataset.source_url == BLS.endpoint()
    assert map_size(dataset.series) == 2
    assert dataset.unavailable == %{"CUUR0000SA0" => [], "LNS14000000" => []}
    assert length(dataset.series["CUUR0000SA0"]) == 240
    assert hd(dataset.series["CUUR0000SA0"]).date == ~D[2006-01-01]
    assert List.last(dataset.series["CUUR0000SA0"]).date == ~D[2025-12-01]

    assert_received {:payload, first_payload}
    refute Map.has_key?(first_payload, "registrationkey")
    assert_received {:payload, second_payload}
    refute Map.has_key?(second_payload, "registrationkey")
  end

  test "retains unavailable monthly source records and their footnotes" do
    body = %{
      "status" => "REQUEST_SUCCEEDED",
      "message" => [],
      "Results" => %{
        "series" => [
          %{
            "seriesID" => "CUUR0000SA0",
            "data" => [
              %{
                "year" => "2025",
                "period" => "M10",
                "value" => "-",
                "footnotes" => [
                  %{"text" => "Data unavailable due to the 2025 lapse in appropriations."}
                ]
              }
            ]
          }
        ]
      }
    }

    assert {:ok, parsed, []} = BLS.parse_response(body)
    assert parsed.series["CUUR0000SA0"] == []

    assert parsed.unavailable["CUUR0000SA0"] == [
             %{
               date: ~D[2025-10-01],
               value: "-",
               footnotes: ["Data unavailable due to the 2025 lapse in appropriations."]
             }
           ]
  end

  test "marks preliminary monthly source values from BLS footnotes" do
    body = %{
      "status" => "REQUEST_SUCCEEDED",
      "message" => [],
      "Results" => %{
        "series" => [
          %{
            "seriesID" => "CUUR0000SA0",
            "data" => [
              %{
                "year" => "2026",
                "period" => "M06",
                "value" => "333.952",
                "footnotes" => [%{"text" => "Preliminary."}]
              },
              %{
                "year" => "2026",
                "period" => "M07",
                "value" => "333.918",
                "footnotes" => [%{"code" => "P", "text" => "Preliminary."}]
              }
            ]
          }
        ]
      }
    }

    assert {:ok, parsed, []} = BLS.parse_response(body)

    assert parsed.series["CUUR0000SA0"] == [
             %{date: ~D[2026-06-01], value: 333.952, preliminary?: true},
             %{date: ~D[2026-07-01], value: 333.918, preliminary?: true}
           ]
  end

  test "rejects an unsuccessful BLS status" do
    assert {:error, {:bls_request_failed, "REQUEST_FAILED", ["bad request"]}} =
             BLS.parse_response(%{
               "status" => "REQUEST_FAILED",
               "message" => ["bad request"]
             })
  end
end
