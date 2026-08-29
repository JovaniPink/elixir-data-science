alias ElixirDataScience.{QCEWComparison, QCEWCrossLanguageVerifier}

default_artifact_paths = QCEWComparison.default_artifact_paths()

{options, arguments, invalid} =
  OptionParser.parse(System.argv(),
    strict: [
      elixir_result: :string,
      elixir_manifest: :string,
      python_result: :string,
      python_manifest: :string
    ]
  )

python_result = options[:python_result]
python_manifest = options[:python_manifest]

if arguments != [] or invalid != [] or is_nil(python_result) or is_nil(python_manifest) do
  IO.puts(
    :stderr,
    "Usage: mix run scripts/verify_qcew_comparison.exs " <>
      "--python-result PATH --python-manifest PATH " <>
      "[--elixir-result PATH] [--elixir-manifest PATH]"
  )

  System.halt(2)
end

verifier_options = [
  elixir_result_path: options[:elixir_result] || default_artifact_paths.result_path,
  elixir_manifest_path: options[:elixir_manifest] || default_artifact_paths.manifest_path,
  python_result_path: python_result,
  python_manifest_path: python_manifest
]

case QCEWCrossLanguageVerifier.verify(verifier_options) do
  {:ok, report} ->
    IO.puts(QCEWCrossLanguageVerifier.format_report(report))

  {:error, %{status: :mismatch} = report} ->
    IO.puts(:stderr, QCEWCrossLanguageVerifier.format_report(report))
    System.halt(1)

  {:error, reason} ->
    IO.puts(:stderr, "QCEW cross-language verification input failed: #{inspect(reason)}")
    System.halt(2)
end
