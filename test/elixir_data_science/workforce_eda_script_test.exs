defmodule ElixirDataScience.WorkforceEdaScriptTest do
  use ExUnit.Case, async: true

  @script "scripts/run_workforce_eda.exs"
  @fixture "test/fixtures/workforce/synthetic.csv"
  @release "test/fixtures/workforce/release.json"
  @regions ~w(01 02 04 05 06 08 09 10 11 12 13 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 44 45 46 47 48 49 50 51 53 54 55 56)

  setup do
    root = Path.join(System.tmp_dir!(), "workforce-eda-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "fixture matches its documented generation rule and release hash" do
    bytes = File.read!(@fixture)

    expected =
      @regions
      |> Enum.with_index(1)
      |> Enum.map(fn {region, index} -> "#{region},#{100 * index * index},jobs\n" end)

    assert bytes == IO.iodata_to_binary(["region,employment,unit\n" | expected])
    assert :json.decode(File.read!(@release))["input_sha256"] == sha256(bytes)
  end

  test "synthetic run binds the receipt to the release input hash", %{root: root} do
    output = Path.join(root, "out")
    assert {_, 0} = run_script([@fixture, output, @release])

    receipt = :json.decode(File.read!(Path.join(output, "analysis-run.v2.json")))
    expected = sha256(File.read!(@fixture))
    assert receipt["input_sha256"] == expected
    assert receipt["release"]["input_sha256"] == expected
  end

  test "synthetic run fails closed when input bytes differ from the release", %{root: root} do
    input = Path.join(root, "tampered.csv")
    File.write!(input, String.replace(File.read!(@fixture), "01,100,jobs", "01,101,jobs"))
    output = Path.join(root, "out")

    assert {message, status} = run_script([input, output, @release])
    assert status != 0
    assert message =~ "input differs from release reference hash"
    refute File.exists?(output)
  end

  test "synthetic run fails closed when the release omits the input hash", %{root: root} do
    release = Path.join(root, "release.json")
    File.write!(release, ~s({"synthetic": true}))
    output = Path.join(root, "out")

    assert {message, status} = run_script([@fixture, output, release])
    assert status != 0
    assert message =~ "input differs from release reference hash"
    refute File.exists?(output)
  end

  @spec run_script([String.t()]) :: {String.t(), non_neg_integer()}
  defp run_script(args) do
    System.cmd(System.find_executable("elixir"), [@script | args], stderr_to_stdout: true)
  end

  @spec sha256(binary()) :: String.t()
  defp sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
end
