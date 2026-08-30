# Regional expert ensemble contract

Checked August 29, 2026.

This experiment predicts next-quarter state employment year-over-year log
growth in a point-in-time historical backtest. It covers the 50 states and
Washington, DC and excludes territories. It is not a causal, recession,
trading, or financial-advice system.

The shared contract is
`contracts/regional-expert-ensemble.v1.json`. Generated source bytes,
normalized observations, panels, folds, predictions, fitted state, and
manifests belong under ignored `data/` or `artifacts/` directories.

The source boundary requires the exact contract hash; receipt-backed BLS QCEW,
BEA, and FHFA files; and complete state/DC vintages. Admission fails on wrong
publisher hosts, missing or duplicate states, post-cutoff releases, nonpositive
log inputs, cache hash/size mismatches, and post-origin features. Live publisher
retrieval and FHFA PDF-layout approval remain manual evidence gates; CI uses
only synthetic source bytes.

Run Elixir from a locally admitted bundle:

```bash
mix run scripts/build_regional_source_bundle.exs \
  --candidate-bundle data/regional/candidate/regional-source-bundle.v1.json \
  --output-dir data/regional/v1

mix run scripts/run_regional_expert_ensemble.exs \
  --source-bundle data/regional/v1/regional-source-bundle.v1.json \
  --output-dir artifacts/regional-ensemble/elixir/v1
```

The builder reuses only hash-verified local source files by default. Add
`--refresh-source` explicitly to redownload receipt-pinned publisher URLs; it
admits the refresh only when byte count and SHA-256 match the predeclared
receipt and refuses to overwrite an unmanaged cache path.

Verify independent output sets without writing a report:

```bash
mix run scripts/verify_regional_expert_ensemble.exs \
  --elixir-dir artifacts/regional-ensemble/elixir/v1 \
  --python-dir /path/to/python-data-science/artifacts/regional-ensemble/python/v1
```

Panel and fold files must be byte-identical. Deterministic predictions use an
absolute tolerance of `1.0e-6`; neural rows require identical eligibility,
finite predictions, weights in `[0,1]`, and weights summing to one.

On August 29, 2026, both implementations consumed the same complete synthetic
multi-vintage bundle spanning 2015 Q1 through 2025 Q4. The no-write verifier
reported `MATCH`. This proves the executable replication contract, not
real-world forecast quality.
