alias ElixirDataScience.{BLS, MacroClustering}

Nx.global_default_backend(EXLA.Backend)
Nx.Defn.global_default_options(compiler: EXLA, client: :host)

start_year = 2006
end_year = 2025

with {:ok, dataset} <- BLS.fetch(start_year, end_year),
     observations <- MacroClustering.observations(dataset),
     {:ok, analysis} <- MacroClustering.cluster(observations, num_clusters: 3, seed: 42) do
  IO.puts("BLS macro clustering: #{start_year}-#{end_year}")
  IO.puts("Retrieved at: #{DateTime.to_iso8601(dataset.retrieved_at)}")
  IO.puts("Aligned observations: #{length(observations)}")
  IO.puts("Inertia: #{Float.round(analysis.inertia, 4)}")

  dataset.unavailable
  |> Enum.flat_map(fn {series_id, points} ->
    Enum.map(points, &{series_id, &1})
  end)
  |> Enum.each(fn {series_id, point} ->
    IO.puts(
      "Unavailable source value: series=#{series_id} month=#{point.date} " <>
        "footnotes=#{Enum.join(point.footnotes, " | ")}"
    )
  end)

  analysis.profiles
  |> Enum.sort_by(& &1.mean_inflation_yoy)
  |> Enum.each(fn profile ->
    IO.puts(
      "cluster=#{profile.cluster} months=#{profile.months} " <>
        "mean_inflation=#{Float.round(profile.mean_inflation_yoy, 2)}% " <>
        "mean_unemployment=#{Float.round(profile.mean_unemployment_rate, 2)}%"
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
