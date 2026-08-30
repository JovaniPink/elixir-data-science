alias ElixirDataScience.RegionalCrossLanguageVerifier, as: Verifier

{options, arguments, invalid} =
  OptionParser.parse(System.argv(),
    strict: [elixir_dir: :string, python_dir: :string]
  )

if arguments != [] or invalid != [] or is_nil(options[:elixir_dir]) or
     is_nil(options[:python_dir]) do
  IO.puts(
    :stderr,
    "Usage: mix run scripts/verify_regional_expert_ensemble.exs --elixir-dir DIR --python-dir DIR"
  )

  System.halt(2)
end

case Verifier.verify(options[:elixir_dir], options[:python_dir]) do
  {:ok, report} ->
    IO.puts(Verifier.format_report(report))

  {:error, report} ->
    IO.puts(:stderr, Verifier.format_report(report))
    System.halt(1)
end
