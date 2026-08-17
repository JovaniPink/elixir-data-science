defmodule ElixirDataScience.Charts do
  @moduledoc "Vega-Lite chart specifications for the BLS macro experiment."

  alias VegaLite, as: Vl

  @doc "Builds vertically aligned inflation and unemployment time-series views."
  @spec timeline([map()]) :: VegaLite.t()
  def timeline(observations) do
    data = chart_rows(observations)

    Vl.new(title: "Observed BLS macro indicators by month", width: 760)
    |> Vl.data_from_values(data)
    |> Vl.concat(
      [
        Vl.new(height: 220)
        |> Vl.mark(:line, point: false, color: "#7c3aed")
        |> Vl.encode_field(:x, "date", type: :temporal, title: nil)
        |> Vl.encode_field(:y, "inflation_yoy",
          type: :quantitative,
          title: "CPI-U inflation (12-month %)"
        ),
        Vl.new(height: 220)
        |> Vl.mark(:line, point: false, color: "#0f766e")
        |> Vl.encode_field(:x, "date", type: :temporal, title: "Month")
        |> Vl.encode_field(:y, "unemployment_rate",
          type: :quantitative,
          title: "Unemployment rate (%)"
        )
      ],
      :vertical
    )
  end

  @doc "Builds a scatterplot of the two standardized clustering inputs."
  @spec scatter([map()]) :: VegaLite.t()
  def scatter(observations) do
    observations
    |> chart_rows()
    |> then(fn data ->
      Vl.new(
        title: "Descriptive K-means clusters (IDs are arbitrary)",
        width: 700,
        height: 460
      )
      |> Vl.data_from_values(data)
      |> Vl.mark(:point, filled: true, size: 55, opacity: 0.78)
      |> Vl.encode_field(:x, "inflation_yoy",
        type: :quantitative,
        title: "CPI-U inflation (12-month %)"
      )
      |> Vl.encode_field(:y, "unemployment_rate",
        type: :quantitative,
        title: "Civilian unemployment rate (%)"
      )
      |> Vl.encode_field(:color, "cluster", type: :nominal, title: "Cluster ID")
      |> Vl.encode(:tooltip, [
        [field: "date", type: :temporal, title: "Month"],
        [field: "inflation_yoy", type: :quantitative, title: "Inflation", format: ".2f"],
        [
          field: "unemployment_rate",
          type: :quantitative,
          title: "Unemployment",
          format: ".1f"
        ],
        [field: "cluster", type: :nominal, title: "Cluster ID"]
      ])
    end)
  end

  defp chart_rows(observations) do
    Enum.map(observations, fn observation ->
      %{
        "date" => Date.to_iso8601(observation.date),
        "inflation_yoy" => observation.inflation_yoy,
        "unemployment_rate" => observation.unemployment_rate,
        "cluster" => observation |> Map.get(:cluster, "unassigned") |> to_string()
      }
    end)
  end
end
