# Documentation guide

This directory separates research context, source rights and provenance, and
executed experiment evidence. Start here when reviewing the repository without
running the Elixir project.

## Reading paths

| Goal | Document | What it establishes |
|---|---|---|
| Understand the Elixir ecosystem | [Elixir for data science and machine learning](elixir-data-science-ecosystem.md) | A dated map of the Elixir, Nx, Explorer, Scholar, Axon, and Livebook ecosystem, including limitations |
| Review the source boundary | [BLS Public Data API source record](data-sources/bls-public-data-api.md) | Series definitions, terms, retrieval behavior, transformations, missing-source treatment, and claim limits |
| Review the QCEW source boundary | [BLS QCEW Open Data source record](data-sources/bls-qcew-open-data.md) | Fixed slice, public-domain status, BLS terms, permitted use, exact grouping contract, and claim limits |
| Produce and verify the QCEW experiment in Python | [QCEW Elixir-Python comparison contract](experiments/qcew-comparison.md) | Generated artifacts, manifest fields, benchmark scope, state labels, production checklist, and exact mismatch command |
| Review the latest observed result | [BLS macro clustering run record: August 26, 2026](experiments/bls-macro-clustering-2026-08-26.md) | The exact executed configuration through July 2026, observed profiles, unavailable and preliminary values, and bounded interpretation |
| Review the predictive validation contract | [Regional expert ensemble contract](experiments/regional-expert-ensemble.md) | Point-in-time source admission, expanding folds, paired implementations, verifier tolerances, and claim limits |
| Review the regional data roadmap | [Regional expert ensemble data roadmap](experiments/regional-expert-ensemble-data-roadmap.md) | Synthetic evidence boundary, intended first-party inputs, and the ordered plan for future experts |
| Match the BLS macro output by meaning | [BLS macro conformance report](experiments/bls-macro-conformance.md) | Versioned JSON fields, label-independent profiles, comparison tolerance, and generated path |
| Review the prior observed result | [BLS macro clustering run record: August 16, 2026](experiments/bls-macro-clustering.md) | The preserved 2006-2025 run before the 2026 sample extension |
| Reproduce interactively | [BLS macro clustering Livebook](../notebooks/bls_macro_clustering.livemd) | The executable notebook backed by the repository lockfile |

The root [README](../README.md) remains the operational entry point for setup,
validation, CLI execution, and opening Livebook.

## Cross-language replication

The sibling
[Python data-science repository](https://github.com/JovaniPink/python-data-science)
independently implements the same bounded question with Polars,
scikit-learn, Vega-Altair, and marimo. Its
[documentation guide](https://github.com/JovaniPink/python-data-science/blob/main/docs/README.md)
links the Python research, source, and run records.

The two implementations intentionally share a January 2006 through December
2025 base sample:

- first-party BLS series `CUUR0000SA0` and `LNS14000000`;
- 12-month CPI-U change and unemployment-rate level as features;
- explicit exclusion, without imputation, of unavailable October 2025 data;
- population standardization, three K-means clusters, seed 42, and 20 starts;
- neutral profile reporting and the same non-causal, non-predictive claim
  boundary.

The August 26, 2026 Elixir run extends its fixed API request end year to 2026
and includes the jointly released observations through July. The linked Python
run remains the preserved 2006-2025 comparison, so the latest Elixir profiles
are not presented as a current cross-language replication.

They do not share runtime code, dataframe libraries, clustering
implementations, or notebook systems. Agreement of the observed profile groups
up to arbitrary cluster-label permutation is an implementation cross-check,
not proof that the clusters are objective economic regimes. The Python
experiment additionally reports a bounded `k=2..6` sensitivity table; that
diagnostic does not retroactively select or validate the Elixir model.

The broader
[Awesome Economic Data catalog](https://github.com/JovaniPink/awesome-economic-data)
is useful for discovering candidate sources. Inclusion in that catalog is not
permission to retrieve, train on, redistribute, or publish a source.

## Documentation contract

- Keep research snapshots dated and distinguish observed ecosystem state from
  permanent compatibility claims.
- Record source terms, access limits, retrieval dates, transformations, missing
  values, and permitted use before adding a dataset.
- Keep source observations, repository-derived transformations, model output,
  and interpretation visibly separate.
- Add a new run record rather than silently replacing historical output when a
  source revision changes results.
- Treat links to sibling implementations as comparison context, not as shared
  validation or evidence of causal meaning.
