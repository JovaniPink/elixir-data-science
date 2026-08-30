alias ElixirDataScience.RegionalSourceBuilder

{options, arguments, invalid} =
  OptionParser.parse(System.argv(),
    strict: [candidate_bundle: :string, output_dir: :string, refresh_source: :boolean]
  )

if arguments != [] or invalid != [] or is_nil(options[:candidate_bundle]) do
  IO.puts(
    :stderr,
    "Usage: mix run scripts/build_regional_source_bundle.exs --candidate-bundle PATH [--output-dir DIR] [--refresh-source]"
  )

  System.halt(2)
end

output_dir = options[:output_dir] || "data/regional/v1"

case RegionalSourceBuilder.build(options[:candidate_bundle], output_dir,
       refresh_source: options[:refresh_source] || false
     ) do
  {:ok, report} ->
    IO.puts("Regional source bundle admitted")
    IO.puts("Contract SHA-256: #{report["contract_sha256"]}")
    IO.puts("Sources: #{report["source_count"]}")
    IO.puts("Refresh requested: #{report["refresh_source"]}")
    IO.puts("Output: #{report["output_dir"]}")

  {:error, reason} ->
    IO.puts(:stderr, "Regional source bundle failed: #{inspect(reason)}")
    System.halt(1)
end
