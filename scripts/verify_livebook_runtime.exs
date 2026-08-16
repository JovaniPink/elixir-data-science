project_path = Path.expand("..", __DIR__)

Mix.install(
  [{:elixir_data_science, path: project_path, env: :dev}],
  lockfile: Path.join(project_path, "mix.lock")
)

alias ElixirDataScience.{Charts, MacroClustering}

Nx.global_default_backend(EXLA.Backend)
Nx.Defn.global_default_options(compiler: EXLA, client: :host)

observations = [
  %{date: ~D[2020-01-01], inflation_yoy: 1.0, unemployment_rate: 4.0, preliminary?: false},
  %{date: ~D[2020-02-01], inflation_yoy: 1.2, unemployment_rate: 4.1, preliminary?: false},
  %{date: ~D[2020-03-01], inflation_yoy: 2.5, unemployment_rate: 7.0, preliminary?: false},
  %{date: ~D[2020-04-01], inflation_yoy: 2.7, unemployment_rate: 7.2, preliminary?: false},
  %{date: ~D[2020-05-01], inflation_yoy: 6.0, unemployment_rate: 4.2, preliminary?: false},
  %{date: ~D[2020-06-01], inflation_yoy: 6.2, unemployment_rate: 4.3, preliminary?: false}
]

{:ok, analysis} =
  MacroClustering.cluster(observations, num_clusters: 3, seed: 42, num_runs: 5)

dataframe = MacroClustering.to_dataframe(analysis)
timeline = analysis.observations |> Charts.timeline() |> Kino.VegaLite.new()
scatter = analysis.observations |> Charts.scatter() |> Kino.VegaLite.new()

unless Explorer.DataFrame.n_rows(dataframe) == 6 and
         is_map(timeline) and Map.has_key?(timeline, :__struct__) and
         is_map(scatter) and Map.has_key?(scatter, :__struct__) do
  raise "Livebook runtime verification failed"
end

IO.puts("Livebook runtime verification passed")
