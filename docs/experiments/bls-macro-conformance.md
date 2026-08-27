# BLS macro conformance report

_Comparison contract added August 27, 2026._

## Purpose

The BLS macro runner emits a versioned JSON report that another implementation
can reproduce and compare without copying available BLS source values into the
artifact. The report is written to the ignored path:

```text
artifacts/bls-macro-conformance/v1/bls-macro-conformance.v1.json
```

Run the existing experiment command:

```bash
mix run scripts/run_bls_macro_clustering.exs
```

The report records the source endpoint, UTC retrieval time, anonymous request
mode, request windows, series identities, feature formulas, population
standardization rule, missing and preliminary-value handling, clustering
settings, aligned month identities, and descriptive profile output. It does
not include the raw API response or available source values. A registered
request is rejected rather than mislabeled as the fixed anonymous experiment.

## Comparison rules

Cluster labels from K-means are arbitrary. The report therefore removes the
Scholar cluster number from profile identity, sorts profiles by their observed
means and assigned months, and assigns `profile_1`, `profile_2`, and
`profile_3`. A matching implementation should compare:

1. Request windows and aligned month identities exactly.
2. Missing and preliminary metadata exactly.
3. Assigned months for each comparison profile exactly.
4. Floating-point summaries with the contract tolerance of `1.0e-6`.
5. Configuration values exactly, including initialization, maximum iterations,
   repeated runs, seed, and convergence tolerance.

The report builder rejects mismatched request metadata, source identity,
analysis settings, source-derived observations, and cluster-label boundaries.
Its tests use synthetic BLS-shaped data and mutation checks; they do not assert
that a later live BLS response will contain the same values.

## Claim boundary

The report is an engineering comparison artifact. It does not establish
causality, forecast a future value, classify a recession, recommend a trade, or
provide financial advice. Source rights, terms, and measurement limits remain
documented in the [BLS source record](../data-sources/bls-public-data-api.md).
