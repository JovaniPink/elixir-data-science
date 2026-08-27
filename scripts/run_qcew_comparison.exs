alias ElixirDataScience.QCEWComparison

{options, arguments, invalid} =
  OptionParser.parse(System.argv(),
    strict: [
      iterations: :integer,
      refresh_source: :boolean,
      source_path: :string,
      output_dir: :string,
      host_hardware_label: :string,
      host_cpu_model: :string,
      host_logical_processors: :integer,
      host_memory_bytes: :integer
    ],
    aliases: [n: :iterations]
  )

if arguments != [] or invalid != [] do
  IO.puts(
    :stderr,
    "Usage: mix run scripts/run_qcew_comparison.exs " <>
      "[--iterations N] [--refresh-source] [--source-path PATH] [--output-dir PATH] " <>
      "[--host-hardware-label LABEL] [--host-cpu-model MODEL] " <>
      "[--host-logical-processors N] [--host-memory-bytes N]"
  )

  System.halt(2)
end

case QCEWComparison.run(options) do
  {:ok, execution} ->
    manifest = execution.manifest
    source = manifest["source"]
    result = manifest["result"]
    benchmark = manifest["benchmark"]

    IO.puts("QCEW comparison: #{manifest["experiment_id"]}")
    IO.puts("Source: #{source["source_url"]}")
    IO.puts("Retrieved at: #{source["retrieved_at"]}")
    IO.puts("Source cache state: #{source["cache_state"]}")
    IO.puts("Source SHA-256: #{source["sha256"]}")
    IO.puts("Source rows: #{result["source_row_count"]}")
    IO.puts("Selected county rows: #{result["selected_row_count"]}")
    IO.puts("Output state rows: #{result["row_count"]}")
    IO.puts("Result SHA-256: #{result["sha256"]}")

    Enum.each(benchmark["measurements"], fn measurement ->
      milliseconds = measurement["elapsed_nanoseconds"] / 1_000_000

      rss_text =
        case measurement["peak_memory"]["rss_bytes"] do
          bytes when is_integer(bytes) -> Float.round(bytes / 1_048_576, 3)
          _other -> "unavailable"
        end

      IO.puts(
        "iteration=#{measurement["iteration"]} " <>
          "state=#{measurement["runtime_state"]} " <>
          "elapsed_ms=#{Float.round(milliseconds, 3)} " <>
          "peak_rss_mib=#{rss_text}"
      )
    end)

    IO.puts("Result: #{execution.result_path}")
    IO.puts("Manifest: #{execution.manifest_path}")

    IO.puts(
      "The output is a deterministic engineering comparison artifact, not a causal, " <>
        "predictive, recession, or financial claim."
    )

    IO.puts(
      "BLS.gov cannot vouch for the data or analyses derived from these data after " <>
        "the data have been retrieved from BLS.gov."
    )

  {:error, reason} ->
    IO.puts(:stderr, "QCEW comparison failed: #{inspect(reason)}")
    System.halt(1)
end
