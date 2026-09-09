# Standalone descriptive peer: elixir scripts/run_workforce_eda.exs INPUT OUTPUT RELEASE_REF
# Uses Erlang/OTP JSON; no Python outputs, cloud credentials, or source downloads.
[input, output, release_ref | materialization_args] = System.argv()
regions = ~w(01 02 04 05 06 08 09 10 11 12 13 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 44 45 46 47 48 49 50 51 53 54 55 56)
bytes = File.read!(input)
sha = fn data -> :crypto.hash(:sha256, data) |> Base.encode16(case: :lower) end
ref = :json.decode(File.read!(release_ref))
binding = if ref["synthetic"] == true do
  nil
else
  [record_path] = materialization_args
  record_bytes = File.read!(record_path)
  record = :json.decode(record_bytes)
  manifest = :json.decode(record["manifest_json"])
  assessment = :json.decode(record["assessment_json"])
  if record["schema_version"] != "verified-materialization.v1" or record["release"] != ref or manifest != record["manifest"] or assessment != record["assessment"], do: raise("verified materialization identity mismatch")
  if sha.(record["manifest_json"]) != ref["sha256"] or byte_size(record["manifest_json"]) != ref["size"], do: raise("manifest differs from pinned bytes")
  if sha.(record["assessment_json"]) != manifest["assessment"]["sha256"], do: raise("assessment differs from pinned bytes")
  if assessment["status"] != "approved" or assessment["use"] != "private_research" or record["purpose"] != "private_research" or assessment["domain"] != manifest["artifact"]["domain"] or not Enum.all?(manifest["source_ids"], &(&1 in assessment["source_ids"])) or not Enum.all?(~w(research transformation storage gcs_storage), &(&1 in assessment["operations"])), do: raise("assessment does not qualify private research")
  relative = Path.relative_to(Path.expand(input), Path.dirname(Path.expand(record_path)))
  if Path.type(relative) == :absolute or ".." in Path.split(relative), do: raise("input outside materialization")
  [item] = Enum.filter(record["objects"], &(&1["path"] == relative))
  if item not in manifest["objects"] or sha.(bytes) != item["object"]["sha256"] or byte_size(bytes) != item["object"]["size"], do: raise("input differs from pinned selection")
  %{"schema_version" => "analysis-input.v1", "release" => ref, "object" => item["object"], "path" => relative, "materialization_sha256" => sha.(record_bytes), "assessment" => manifest["assessment"], "purpose" => "private_research"}
end
[header | lines] = String.split(String.trim(bytes), "\n")
if String.trim(header) != "region,employment,unit", do: raise("expected canonical workforce CSV")
weights = Enum.map(lines, fn line ->
  [region, employment, unit] = String.split(String.trim(line), ",")
  if unit != "jobs", do: raise("employment units must be jobs")
  value = String.to_integer(employment)
  if value < 0, do: raise("nonnegative employment required")
  {region, value}
end)
if length(weights) != 51 or Enum.sort(Enum.map(weights, &elem(&1, 0))) != regions, do: raise("51 unique state/DC rows required")
weights = Map.new(weights)
total = Enum.sum(Map.values(weights))
if total <= 0, do: raise("positive employment required")
allocate = fn count ->
  initial = Map.new(weights, fn {key, value} -> {key, div(count * value, total)} end)
  remainder = count - Enum.sum(Map.values(initial))
  keys = Enum.sort_by(regions, fn key -> {-rem(count * weights[key], total), key} end)
  Enum.reduce(Enum.take(keys, remainder), initial, fn key, acc -> Map.update!(acc, key, &(&1 + 1)) end)
end
requests = allocate.(1000)
extras = allocate.(51)
values = Enum.sort(Map.values(weights))
result = %{
  "schema_version" => "workforce-eda.v1", "input_sha256" => sha.(bytes), "row_ids" => regions,
  "missingness" => 0, "coverage" => %{"present" => 51, "expected" => 51}, "total_employment" => total,
  "distribution" => %{"min" => hd(values), "median" => Enum.at(values, 25), "max" => List.last(values), "mean" => total / 51},
  "regions" => Enum.map(regions, fn key -> %{"region" => key, "employment" => weights[key], "share" => weights[key] / total, "requests" => requests[key], "uniform_slots" => 2, "weighted_slots" => 1 + extras[key]} end)
}
File.mkdir_p!(output)
encoded = IO.iodata_to_binary(:json.encode(result))
File.write!(Path.join(output, "workforce-eda.v1.json"), encoded)
receipt = %{"schema_version" => "analysis-run.v2", "input_binding" => binding, "language" => "elixir", "release" => ref, "input_sha256" => sha.(bytes), "output_sha256" => sha.(encoded), "environment" => System.version(), "code_sha256" => sha.(File.read!(__ENV__.file)), "method" => "descriptive-largest-remainder.v1", "evidence_mode" => if(ref["synthetic"], do: "synthetic", else: "current-snapshot")}
File.write!(Path.join(output, "eda.md"), "# Workforce EDA\n\n51 state/DC rows; total employment #{total} jobs.\n\nEmployment supplies weights for synthetic requests and resources. No forecast claim.\n")
receipt = Map.put(receipt, "report_sha256", sha.(File.read!(Path.join(output, "eda.md"))))
File.write!(Path.join(output, "analysis-run.v2.json"), :json.encode(receipt))
