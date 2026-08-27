# BLS macro conformance report contract

## Purpose

The Elixir and sibling Python experiments use independent runtime code and
libraries. A generated conformance report lets them test whether they retrieved
and analyzed the same 2006-2026 BLS sample without committing source data or
generated model artifacts.

The report schema is `bls-macro-conformance.v1`. It is a comparison contract,
not a claim that either implementation validates the clusters as economic
regimes.

## Generate the report

From the repository root, run:

```bash
mix run scripts/generate_bls_conformance_report.exs
```

The default output is `artifacts/bls-macro-conformance.json`. Use
`--output PATH` to write to another generated location. The default directory
is ignored by Git, and the report must not be staged or committed. The runtime
request does not save the raw BLS response or available monthly source values.

## Report sections

| Section | Comparison evidence |
|---|---|
| `request` | Inclusive 2006-2026 bounds, anonymous 10-year windows, and ordered series IDs |
| `source` | First-party endpoint, portable series definitions, per-series coverage, API messages, and retrieval context |
| `alignment` | Exact ordered month list, first and last month, count, 12-month warmup, and inner-join rule |
| `value_handling` | Unavailable records and footnotes, no-imputation policy, preliminary detection, source records, and propagation to aligned months |
| `features` | Ordered feature names, source series, formulas, lags, and units |
| `standardization` | Population z-score formula, zero degrees of freedom, and observed feature summaries |
| `clustering` | K-means++, three clusters, seed 42, 20 starts, 300 maximum iterations, tolerance `1.0e-4`, and implementation-only runtime details |
| `descriptive_output` | Neutral claim boundary and profiles with means, counts, bounds, and every assigned month |
| `comparison` | Exact fields, tolerance-based numeric fields, informational fields, and absolute numeric tolerance |

## Cross-language comparison procedure

1. Generate Elixir and Python reports from independent BLS requests made close
   enough together that the source coverage and revision state should match.
2. Confirm both reports use schema `bls-macro-conformance.v1`.
3. Compare every path in `comparison.exact_fields` exactly after parsing JSON.
4. Compare every path in `comparison.numeric_fields` with absolute tolerance
   `comparison.numeric_tolerance`, currently `1.0e-6`.
5. Match clusters by `comparison_profile_id`, which is assigned after sorting
   profiles by the documented descriptive values. Do not compare arbitrary
   implementation cluster IDs.
6. Treat `comparison.informational_fields` as execution context. Differences in
   language metadata, retrieval timestamps, implementation cluster IDs,
   iteration count, or inertia do not by themselves establish nonconformance.
7. If source coverage, API messages, unavailable values, or preliminary flags
   differ, first determine whether BLS changed between retrievals. Do not call a
   source-revision difference an implementation defect without that check.

Exact assigned-month agreement tests the descriptive partition without relying
on cluster labels. The profile means are rounded to six decimal places in the
report and compared with the declared absolute tolerance.

## Artifact and claim boundary

The generated JSON contains coverage metadata, month identities, handling
records, configuration, summaries, and cluster assignments. It deliberately
omits the raw API response and available monthly source values. The repository
also ignores `data/`, `artifacts/`, and `exports/`.

Agreement between the reports is an implementation cross-check for the tested
runtime inputs and settings. It is not causal evidence, a forecast, recession
classification, trading signal, financial advice, or proof that three clusters
are the correct economic model.
