alias ElixirDataScience.RegionalModeling

{options, arguments, invalid} =
  OptionParser.parse(System.argv(), strict: [source_bundle: :string, output_dir: :string])

if arguments != [] or invalid != [] or is_nil(options[:source_bundle]) do
  IO.puts(
    :stderr,
    "Usage: mix run scripts/run_regional_expert_ensemble.exs --source-bundle PATH [--output-dir DIR]"
  )

  System.halt(2)
end

output_dir = options[:output_dir] || "artifacts/regional-ensemble/elixir/v1"

case RegionalModeling.run(options[:source_bundle], output_dir) do
  {:ok, manifest} ->
    IO.puts("Regional expert ensemble: point-in-time historical backtest")
    IO.puts("Contract SHA-256: #{manifest["contract_sha256"]}")
    IO.puts("Artifacts: #{output_dir}")
    IO.puts("This is not a causal, recession, trading, or financial-advice claim.")

  {:error, reason} ->
    IO.puts(:stderr, "Regional expert ensemble failed: #{inspect(reason)}")
    System.halt(1)
end
