# Documentation guide

This directory separates research context, source rights and provenance, and
executed experiment evidence. Start here when reviewing the repository without
running the Elixir project.

## Reading paths

| Goal | Document | What it establishes |
|---|---|---|
| Understand the Elixir ecosystem | [Elixir for data science and machine learning](elixir-data-science-ecosystem.md) | A dated map of the Elixir, Nx, Explorer, Scholar, Axon, and Livebook ecosystem, including limitations |
| Review the source boundary | [BLS Public Data API source record](data-sources/bls-public-data-api.md) | Series definitions, terms, retrieval behavior, transformations, missing-source treatment, and claim limits |
| Review the observed result | [BLS macro clustering run record](experiments/bls-macro-clustering.md) | The exact executed configuration, observed profiles, missing month, and bounded interpretation |
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

The two implementations intentionally share:

- first-party BLS series `CUUR0000SA0` and `LNS14000000`;
- the January 2006 through December 2025 requested sample;
- 12-month CPI-U change and unemployment-rate level as features;
- explicit exclusion, without imputation, of unavailable October 2025 data;
- population standardization, three K-means clusters, seed 42, and 20 starts;
- neutral profile reporting and the same non-causal, non-predictive claim
  boundary.

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
