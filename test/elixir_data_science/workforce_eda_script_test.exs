defmodule ElixirDataScience.WorkforceEdaScriptTest do
  use ExUnit.Case, async: true

  @script "scripts/run_workforce_eda.exs"
  @fixture "test/fixtures/workforce/synthetic.csv"
  @release "test/fixtures/workforce/release.json"
  @regions ~w(01 02 04 05 06 08 09 10 11 12 13 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 44 45 46 47 48 49 50 51 53 54 55 56)

  setup do
    # The materialized run rejects symlinked path components, so avoid a system temp directory
    # that may be one (for example /var on macOS); _build is ignored by Git.
    root =
      Path.join(Mix.Project.build_path(), "workforce-eda-#{System.unique_integer([:positive])}")

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
    assert receipt["input_binding"] == :null
  end

  test "materialized run walks the absolute input path and binds the object", %{root: root} do
    bytes = File.read!(@fixture)
    input = Path.join(root, "synthetic.csv")
    File.write!(input, bytes)
    object = %{"sha256" => sha256(bytes), "size" => byte_size(bytes)}
    item = %{"path" => "synthetic.csv", "object" => object}

    assessment = %{
      "status" => "approved",
      "use" => "private_research",
      "domain" => "workforce",
      "source_ids" => ["synthetic"],
      "operations" => ~w(research transformation storage gcs_storage)
    }

    assessment_json = encode(assessment)

    manifest = %{
      "artifact" => %{"domain" => "workforce"},
      "assessment" => %{"sha256" => sha256(assessment_json)},
      "source_ids" => ["synthetic"],
      "objects" => [item]
    }

    manifest_json = encode(manifest)
    ref = %{"sha256" => sha256(manifest_json), "size" => byte_size(manifest_json)}

    record = %{
      "schema_version" => "verified-materialization.v1",
      "release" => ref,
      "manifest_json" => manifest_json,
      "manifest" => manifest,
      "assessment_json" => assessment_json,
      "assessment" => assessment,
      "purpose" => "private_research",
      "verifier_version" => "workforce-eda-script-test",
      "objects" => [item]
    }

    release = Path.join(root, "release.json")
    record_path = Path.join(root, "materialization.json")
    File.write!(release, encode(ref))
    output = Path.join(root, "out")

    File.write!(record_path, encode(Map.delete(record, "verifier_version")))
    assert {message, status} = run_script([input, output, release, record_path])
    assert status != 0
    assert message =~ "verified materialization envelope incomplete"
    refute File.exists?(output)

    File.write!(record_path, encode(record))
    assert {_, 0} = run_script([input, output, release, record_path])

    receipt = :json.decode(File.read!(Path.join(output, "analysis-run.v2.json")))
    assert receipt["evidence_mode"] == "current-snapshot"
    assert receipt["input_binding"]["path"] == "synthetic.csv"
    assert receipt["input_binding"]["object"] == object
    assert receipt["input_binding"]["materialization_sha256"] == sha256(File.read!(record_path))
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

  @spec encode(map()) :: binary()
  defp encode(term), do: IO.iodata_to_binary(:json.encode(term))

  @spec sha256(binary()) :: String.t()
  defp sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
end
