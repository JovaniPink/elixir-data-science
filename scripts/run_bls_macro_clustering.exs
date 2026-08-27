alias ElixirDataScience.{BLS, BLSConformanceReport, BLSMacroExperiment, MacroClustering}

Nx.global_default_backend(EXLA.Backend)
Nx.Defn.global_default_options(compiler: EXLA, client: :host)

config = BLSMacroExperiment.configuration()
report_path = "artifacts/bls-macro-conformance/v1/bls-macro-conformance.v1.json"

with {:ok, dataset} <- BLS.fetch(config.start_year, config.end_year),
     observations <- MacroClustering.observations(dataset),
     {:ok, analysis} <- MacroClustering.cluster(observations, config.cluster_options),
     {:ok, report} <- BLSConformanceReport.build(dataset, analysis, config),
     :ok <- BLSConformanceReport.write(report, report_path) do
  unavailable_points =
    dataset.unavailable
    |> Enum.flat_map(fn {series_id, points} ->
      Enum.map(points, &{series_id, &1})
    end)
    |> Enum.sort_by(fn {series_id, point} -> {point.date, series_id} end)

  preliminary_points =
    dataset.series
    |> Enum.flat_map(fn {series_id, points} ->
      points
      |> Enum.filter(& &1.preliminary?)
      |> Enum.map(&{series_id, &1})
    end)
    |> Enum.sort_by(fn {series_id, point} -> {point.date, series_id} end)

  IO.puts("BLS macro clustering: #{config.start_year}-#{config.end_year}")
  IO.puts("Retrieved at: #{DateTime.to_iso8601(dataset.retrieved_at)}")
  IO.puts("Aligned observations: #{length(observations)}")
  IO.puts("Aligned period: #{hd(observations).date} through #{List.last(observations).date}")
  IO.puts("Preliminary aligned observations: #{Enum.count(observations, & &1.preliminary?)}")
  IO.puts("Inertia: #{Float.round(analysis.inertia, 4)}")
  IO.puts("API messages: #{length(dataset.messages)}")
  IO.puts("Conformance report: #{report_path}")

  Enum.each(dataset.messages, &IO.puts("API message: #{&1}"))

  IO.puts("Unavailable source values: #{length(unavailable_points)}")

  Enum.each(unavailable_points, fn {series_id, point} ->
    IO.puts(
      "Unavailable source value: series=#{series_id} month=#{point.date} " <>
        "footnotes=#{Enum.join(point.footnotes, " | ")}"
    )
  end)

  IO.puts("Preliminary source values: #{length(preliminary_points)}")

  Enum.each(preliminary_points, fn {series_id, point} ->
    IO.puts(
      "Preliminary source value: series=#{series_id} month=#{point.date} value=#{point.value}"
    )
  end)

  analysis.profiles
  |> Enum.sort_by(& &1.mean_inflation_yoy)
  |> Enum.each(fn profile ->
    IO.puts(
      "cluster=#{profile.cluster} months=#{profile.months} " <>
        "mean_inflation=#{Float.round(profile.mean_inflation_yoy, 2)}% " <>
        "mean_unemployment=#{Float.round(profile.mean_unemployment_rate, 2)}% " <>
        "period=#{profile.first_month}..#{profile.last_month}"
    )
  end)

  IO.puts(
    "\nCluster IDs are arbitrary and descriptive; this is not a forecast or investment advice."
  )

  IO.puts(
    "BLS.gov cannot vouch for the data or analyses derived from these data after the data have been retrieved from BLS.gov."
  )
else
  {:error, reason} ->
    IO.puts(:stderr, "Experiment failed: #{inspect(reason)}")
    System.halt(1)
end
