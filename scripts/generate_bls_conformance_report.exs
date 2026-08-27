alias ElixirDataScience.{
  BLS,
  BLSConformanceReport,
  BLSMacroExperiment,
  MacroClustering
}

Nx.global_default_backend(EXLA.Backend)
Nx.Defn.global_default_options(compiler: EXLA, client: :host)

default_output_path = Path.expand("../#{BLSConformanceReport.default_output_path()}", __DIR__)

output_path =
  case OptionParser.parse(System.argv(), strict: [output: :string]) do
    {[output: path], [], []} ->
      Path.expand(path)

    {[], [], []} ->
      default_output_path

    _ ->
      IO.puts(
        :stderr,
        "Usage: mix run scripts/generate_bls_conformance_report.exs [--output PATH]"
      )

      System.halt(2)
  end

config = BLSMacroExperiment.configuration()

with {:ok, dataset} <- BLS.fetch(config.start_year, config.end_year),
     observations <- MacroClustering.observations(dataset),
     {:ok, analysis} <- MacroClustering.cluster(observations, config.cluster_options),
     {:ok, report} <- BLSConformanceReport.build(dataset, analysis, config),
     :ok <- BLSConformanceReport.write(report, output_path) do
  IO.puts("BLS conformance report: #{output_path}")
  IO.puts("Retrieved at: #{report["retrieved_at_utc"]}")
  IO.puts("Aligned observations: #{report["alignment"]["observation_count"]}")

  IO.puts(
    "Aligned period: #{report["alignment"]["first_month"]} through " <>
      report["alignment"]["last_month"]
  )

  IO.puts(
    "Unavailable source values: " <>
      Integer.to_string(report["value_handling"]["unavailable"]["source_value_count"])
  )

  IO.puts(
    "Preliminary source values: " <>
      Integer.to_string(report["value_handling"]["preliminary"]["source_value_count"])
  )

  IO.puts("The generated JSON artifact and raw BLS data remain outside Git.")
else
  {:error, reason} ->
    IO.puts(:stderr, "Conformance report failed: #{inspect(reason)}")
    System.halt(1)
end
