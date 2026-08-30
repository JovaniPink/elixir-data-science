# Elixir Data Science Experiments

This repository is reserved for small, reviewable experiments at the
intersection of Elixir and data science.

## Current status

Two focused experiments are implemented: a Livebook-first exploration of
monthly U.S. inflation and unemployment, and a bounded QCEW download and
grouping pipeline with field-level verification of independently produced
Python artifacts. Both use first-party BLS data. The QCEW experiment uses
Explorer but does not fit a model.

The experiments retrieve data at runtime and commit no raw dataset, generated
model output, or credentials.

The QCEW source CSV, its hash sidecar, grouped output, and versioned result
manifest are also generated only in the ignored `data/` and `artifacts/`
directories.

The [latest dated run record](docs/experiments/bls-macro-clustering-2026-08-26.md)
preserves the verified output and a bounded interpretation separately from the
live notebook. The [documentation guide](docs/README.md) provides a review path
through the ecosystem brief, source record, executed runs, and sibling Python
replication.

The BLS macro runner also writes an ignored, versioned
[conformance report](docs/experiments/bls-macro-conformance.md) for
label-independent comparison with another implementation.

## Research question

Can K-means separate recurring combinations of observed U.S. CPI inflation and
unemployment in a fixed 2006-2026 request boundary, using the jointly released
observations through July 2026?

The output is descriptive and ex post. Cluster IDs are arbitrary; they are not
objective economic regimes, causal explanations, recession predictions,
trading signals, or financial advice.

## Data source and rights boundary

The runtime source is the [BLS Public Data API](https://www.bls.gov/developers/)
using CPI-U series `CUUR0000SA0` and the seasonally adjusted civilian
unemployment-rate series `LNS14000000`. The
[source record](docs/data-sources/bls-public-data-api.md) documents series
definitions, access limits, current terms, required attribution, retrieval
behavior, transformations, and analytical limitations.

FRED is not the training-data source. Its
[current terms](https://fred.stlouisfed.org/legal/terms/) prohibit using FRED
services or content in connection with developing or training machine-learning
systems, so this experiment retrieves the series directly from BLS under the
reviewed BLS terms.

## Toolchain

- Supported: Elixir 1.19.x-1.20.x and Erlang/OTP 27.x-28.x.
- Tested CI runtimes: Elixir 1.20.2 with Erlang/OTP 27 and Elixir 1.19.5 with
  Erlang/OTP 28.
- Tested notebook runtime: Livebook 0.19.8 with Elixir 1.19.3 and
  Erlang/OTP 28.
- CI containers:
  - `elixir:1.20.2-otp-27` at
    `sha256:998bb64cb24209d959eb48af9bac1a087f4b5b4d32e91f6e67d666659af04bcd`.
  - `elixir:1.19.5-otp-28` at
    `sha256:4eda86b01d2a3448aef341a60ba962a584ed330e33ce526a70b1b6d90ede6e41`.

The exact local asdf versions are recorded in `.tool-versions`; dependency
versions are committed in `mix.lock`.

## Validate

With the supported local toolchain:

```bash
mix deps.get --check-locked
mix hex.audit
mix format --check-formatted
mix test
elixir scripts/verify_livebook_runtime.exs
```

Or without a local Elixir installation:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace \
  elixir:1.20.2-otp-27@sha256:998bb64cb24209d959eb48af9bac1a087f4b5b4d32e91f6e67d666659af04bcd \
  sh -lc 'mix local.hex 2.5.1 --force && mix local.rebar rebar3 https://builds.hex.pm/installs/1.18.3/rebar3-3.24.0-otp-27 --sha512 158473850233093e6a1417e9779919cb6768402ea967db510d926bc5e74361377e9176014e827c622098e0dbf96b505677addc4bd4817ce2b9b4f4bc8121768b --force && mix deps.get --check-locked && mix hex.audit && mix format --check-formatted && mix test && elixir scripts/verify_livebook_runtime.exs'
```

The Hex client, Rebar artifact, and container are immutable in CI. The security
gate fails on retired Hex packages or known advisories; the repository does not
carry advisory suppressions. The test suite also checks tracked and untracked
repository text for printable ASCII and common non-US English spellings.

## Run the analysis

The command below makes three anonymous BLS requests, records the UTC retrieval
time, reports unavailable and preliminary source values, derives the aligned
monthly observations, fits three clusters with a fixed seed, and prints neutral
cluster profiles. It writes no data file. The August 26, 2026 verification
produced 234 observations through July 2026, retained two unavailable October
2025 source values without imputation, and found no values marked preliminary.

```bash
mix run scripts/run_bls_macro_clustering.exs
```

## Run the QCEW comparison

The QCEW command downloads the fixed first-quarter 2024 all-industries slice,
verifies or creates its source sidecar, selects published county total-covered
rows, groups integer measures by state FIPS, and writes a canonical CSV plus a
version 1 JSON manifest. It performs five timed transforms by default and
records sampled peak RSS, BEAM-managed memory, hardware, runtime, and narrowly
defined cold/warm state metadata.

```bash
mix run scripts/run_qcew_comparison.exs
```

See the [QCEW source record](docs/data-sources/bls-qcew-open-data.md) for source,
public-domain status, BLS terms, permitted use, retrieval behavior, fields, and
claim boundaries. The
[cross-language comparison contract](docs/experiments/qcew-comparison.md)
defines exact output bytes, measurement scope, generated paths, the Python
production checklist, and the no-write verification command.

After a Python implementation produces its ignored canonical CSV and version 1
manifest, compare it with the local Elixir artifacts:

```bash
mix run scripts/verify_qcew_comparison.exs \
  --python-result /absolute/path/to/qcew-state-totals.v1.csv \
  --python-manifest /absolute/path/to/qcew-comparison-manifest.v1.json
```

The verifier writes nothing and reports source-contract, artifact-integrity,
canonical-format, row-order, total, and state/column mismatches separately.

This output is a deterministic engineering comparison artifact. It is not a
causal explanation, forecast, recession indicator, trading signal, or financial
advice.

## Run the regional expert ensemble

Use a locally admitted, hash-verified source bundle. Generated artifacts remain
under ignored paths.

```bash
mix run scripts/build_regional_source_bundle.exs \
  --candidate-bundle data/regional/candidate/regional-source-bundle.v1.json \
  --output-dir data/regional/v1

mix run scripts/run_regional_expert_ensemble.exs \
  --source-bundle data/regional/v1/regional-source-bundle.v1.json \
  --output-dir artifacts/regional-ensemble/elixir/v1

mix run scripts/verify_regional_expert_ensemble.exs \
  --elixir-dir artifacts/regional-ensemble/elixir/v1 \
  --python-dir /path/to/python-data-science/artifacts/regional-ensemble/python/v1
```

This is a point-in-time historical backtest, not a causal, recession, trading,
or financial-advice claim. See the
[regional ensemble contract](docs/experiments/regional-expert-ensemble.md).

## Open the Livebook

Open [`notebooks/bls_macro_clustering.livemd`](notebooks/bls_macro_clustering.livemd)
in Livebook Desktop 0.19.8 or run the pinned container from this repository:

```bash
docker run --rm -p 8080:8080 -v "$PWD:/data" \
  ghcr.io/livebook-dev/livebook:0.19.8@sha256:38eed8467d3df794dd36cbe722768e46d709b02e00368e0a06aa7508220a8763
```

Then open `/data/notebooks/bls_macro_clustering.livemd`. The notebook uses the
repository's `mix.lock`, retrieves BLS data at runtime, displays Explorer
tables, and renders VegaLite time-series and cluster views.

## Ecosystem research

The dated [Elixir data science and machine learning ecosystem brief](docs/elixir-data-science-ecosystem.md)
maps the current tools, strengths, limitations, and a possible learning path.
It is the research context for this implementation.

## Experiment contract

Each experiment should arrive as a focused pull request that includes:

1. a clearly stated research question and expected output;
2. a supported Elixir and Erlang/OTP version range;
3. a `mix.exs` and committed `mix.lock` when dependencies are used;
4. deterministic setup, test, and run commands;
5. small fixtures or synthetic data for automated tests; and
6. source, license, retrieval date, and permitted-use notes for any external
   dataset.

Generated notebooks, model outputs, credentials, and large raw datasets should
not be committed by default. Access to a dataset is not evidence that it may be
redistributed.

## Repository contents

- `lib/`: BLS retrieval, transformations, clustering, QCEW grouping,
  measurement, and cross-language verification support.
- `test/`: synthetic BLS-shaped and QCEW-shaped fixtures and deterministic
  tests.
- `notebooks/bls_macro_clustering.livemd`: documented interactive analysis.
- `scripts/run_bls_macro_clustering.exs`: non-notebook execution path.
- `scripts/run_qcew_comparison.exs`: QCEW source, grouping, measurement, and
  manifest execution path.
- `scripts/verify_qcew_comparison.exs`: no-write QCEW Elixir-Python artifact
  verifier.
- `scripts/verify_livebook_runtime.exs`: standalone path/lock/chart check.
- `docs/data-sources/`: source, terms, provenance, and claim boundaries.
- `docs/experiments/`: dated run records and bounded interpretations.
- `docs/README.md`: documentation map and cross-language replication boundary.
- `README.md`: setup, validation, execution, and scope.
- `AGENTS.md`: repository-local contributor guidance.
- `docs/elixir-data-science-ecosystem.md`: dated ecosystem research brief.
- `LICENSE`: license for repository-authored material.

## License

Repository-authored material is available under the [MIT License](LICENSE).
Third-party data and future dependencies remain subject to their own terms.
