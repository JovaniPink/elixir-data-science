defmodule ElixirDataScience.BLSFixture do
  @moduledoc false

  @spec response(pos_integer(), pos_integer()) :: map()
  def response(start_year, end_year) do
    %{
      "status" => "REQUEST_SUCCEEDED",
      "message" => [],
      "Results" => %{
        "series" => [
          series("CUUR0000SA0", start_year, end_year, &cpi_value/2),
          series("LNS14000000", start_year, end_year, &unemployment_value/2)
        ]
      }
    }
  end

  defp series(id, start_year, end_year, value_fun) do
    data =
      for year <- start_year..end_year,
          month <- 1..12 do
        %{
          "year" => Integer.to_string(year),
          "period" => "M" <> String.pad_leading(Integer.to_string(month), 2, "0"),
          "periodName" => Calendar.strftime(Date.new!(year, month, 1), "%B"),
          "value" => value_fun.(year, month) |> :erlang.float_to_binary(decimals: 3),
          "footnotes" => []
        }
      end

    %{"seriesID" => id, "data" => Enum.reverse(data)}
  end

  defp cpi_value(year, month) do
    elapsed_months = (year - 2000) * 12 + month - 1
    100.0 * :math.pow(1.0025, elapsed_months)
  end

  defp unemployment_value(year, month) do
    phase = rem((year - 2000) * 12 + month - 1, 36)

    cond do
      phase < 12 -> 4.0 + month / 100.0
      phase < 24 -> 6.5 + month / 100.0
      true -> 9.0 + month / 100.0
    end
  end
end
