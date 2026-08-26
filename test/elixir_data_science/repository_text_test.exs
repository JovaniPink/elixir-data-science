defmodule ElixirDataScience.RepositoryTextTest do
  use ExUnit.Case, async: true

  @non_us_spellings [
    "analy" <> "se",
    "analy" <> "sed",
    "analy" <> "sing",
    "behavio" <> "ur",
    "behavio" <> "urs",
    "behavio" <> "ural",
    "catalog" <> "ue",
    "cent" <> "re",
    "cent" <> "res",
    "colo" <> "ur",
    "colo" <> "urs",
    "defen" <> "ce",
    "favo" <> "ur",
    "favo" <> "urite",
    "gre" <> "y",
    "fulfil" <> "ment",
    "initial" <> "ise",
    "initial" <> "ised",
    "initial" <> "ising",
    "label" <> "led",
    "label" <> "ling",
    "licen" <> "ce",
    "model" <> "led",
    "model" <> "ling",
    "offen" <> "ce",
    "optim" <> "ise",
    "optim" <> "ised",
    "optim" <> "ising",
    "organi" <> "sation",
    "organi" <> "sations",
    "organi" <> "se",
    "organi" <> "sed",
    "organi" <> "sing",
    "priorit" <> "ise",
    "priorit" <> "ised",
    "priorit" <> "ising",
    "progra" <> "mme",
    "recogni" <> "se",
    "recogni" <> "sed",
    "recogni" <> "sing",
    "standard" <> "ise",
    "standard" <> "ised",
    "standard" <> "ising",
    "summar" <> "ise",
    "summar" <> "ised",
    "summar" <> "ising",
    "synchron" <> "ise",
    "synchron" <> "ised",
    "synchron" <> "ising",
    "travel" <> "led",
    "travel" <> "ler",
    "travel" <> "ling",
    "visual" <> "ise",
    "visual" <> "ised",
    "visual" <> "ising"
  ]

  test "tracked paths and text use printable ASCII US English" do
    violations =
      tracked_files()
      |> Enum.flat_map(fn path ->
        content = File.read!(path)

        path_violations =
          if printable_ascii?(path), do: [], else: ["#{path}: non-ASCII path"]

        content_violations =
          if printable_ascii_text?(content), do: [], else: ["#{path}: non-ASCII content"]

        spelling_violations =
          content
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.flat_map(fn {line, line_number} ->
            non_us_matches(line)
            |> Enum.map(&"#{path}:#{line_number}: non-US spelling #{&1}")
          end)

        path_violations ++ content_violations ++ spelling_violations
      end)

    assert violations == []
  end

  test "text checks detect representative violations" do
    refute printable_ascii_text?("plain" <> <<0xE2, 0x80, 0x93>> <> "text")
    assert non_us_matches("colo" <> "ur") == ["colo" <> "ur"]
  end

  @spec tracked_files() :: [String.t()]
  defp tracked_files do
    repository_path = File.cwd!()

    {output, 0} =
      System.cmd(
        "git",
        [
          "-c",
          "safe.directory=#{repository_path}",
          "ls-files",
          "-z",
          "--cached",
          "--others",
          "--exclude-standard"
        ],
        stderr_to_stdout: true
      )

    output
    |> String.split(<<0>>, trim: true)
    |> Enum.sort()
  end

  @spec printable_ascii?(String.t()) :: boolean()
  defp printable_ascii?(value) do
    value
    |> :binary.bin_to_list()
    |> Enum.all?(&(&1 in 32..126))
  end

  @spec printable_ascii_text?(binary()) :: boolean()
  defp printable_ascii_text?(value) do
    value
    |> :binary.bin_to_list()
    |> Enum.all?(&(&1 in [9, 10, 13] or &1 in 32..126))
  end

  @spec non_us_matches(String.t()) :: [String.t()]
  defp non_us_matches(value) do
    pattern =
      @non_us_spellings
      |> Enum.map(&Regex.escape/1)
      |> Enum.join("|")
      |> then(&Regex.compile!("\\b(?:#{&1})\\b", "i"))

    pattern
    |> Regex.scan(value)
    |> Enum.map(fn [match] -> String.downcase(match) end)
  end
end
