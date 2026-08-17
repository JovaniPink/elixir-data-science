# Project knowledge

This directory separates source provenance, dated experiment evidence, and
ecosystem explanation for the Elixir data-science workspace. The repository
[`README.md`](../README.md) remains the current entry point for setup, supported
runtimes, and validation commands.

## Knowledge map

| Area | Document | Authority |
| --- | --- | --- |
| Source provenance | [`data-sources/bls-public-data-api.md`](data-sources/bls-public-data-api.md) | Access, terms, retrieval, series, and claim boundaries for BLS data |
| Experiment evidence | [`experiments/bls-macro-clustering.md`](experiments/bls-macro-clustering.md) | Dated Elixir execution, run manifest, observed output, and limitations |
| Ecosystem explanation | [`elixir-data-science-ecosystem.md`](elixir-data-science-ecosystem.md) | Dated research on the Elixir data-science ecosystem and its trade-offs |

The independently implemented Python replication is maintained in
[`JovaniPink/python-data-science`](https://github.com/JovaniPink/python-data-science).
Agreement between the two implementations is a reproducibility check; it does
not turn descriptive clusters into causal or predictive evidence.

## Maintenance contract

- Update the source record when access terms, series definitions, or retrieval
  constraints change.
- Add a new dated run record when inputs, dependency versions, model settings,
  or results materially change; do not silently rewrite old evidence.
- Keep observed data, repository transformations, model output, and
  interpretation visibly distinct.
- Record a significant accepted design choice in a decision record only when
  there is a real choice and consequence to preserve. Do not create empty
  documentation categories for symmetry.
