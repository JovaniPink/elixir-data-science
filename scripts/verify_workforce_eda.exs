# Standalone invariant check: elixir scripts/verify_workforce_eda.exs OUTPUT
# Verifies the allocation invariants of a run_workforce_eda.exs output directory and prints it.
[output] = System.argv()

eda = File.read!(Path.join(output, "workforce-eda.v1.json"))
result = :json.decode(eda)

if length(result["row_ids"]) != 51 or
     Enum.sum(Enum.map(result["regions"], & &1["requests"])) != 1000 or
     Enum.sum(Enum.map(result["regions"], & &1["weighted_slots"])) != 102,
   do: raise("workforce allocation invariant failed")

IO.puts("WORKFORCE_EDA_JSON=" <> eda)
IO.puts("WORKFORCE_RECEIPT_JSON=" <> File.read!(Path.join(output, "analysis-run.v2.json")))

IO.puts(
  "WORKFORCE_REPORT_JSON=" <>
    IO.iodata_to_binary(:json.encode(File.read!(Path.join(output, "eda.md"))))
)
