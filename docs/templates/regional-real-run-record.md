# Regional expert ensemble run record: YYYY-MM-DD

_Template only. Copy this file to a new dated experiment record. Do not edit the
template with observed values._

## Claim statement

This is a point-in-time historical backtest for forecast origins 2020 Q1
through 2025 Q3. It predicts next-quarter final QCEW third-month employment
year-over-year log growth for the 50 states and Washington, DC, excluding
territories. Historical features and training outcomes use only publications
available by each calendar quarter-end. Final QCEW values are used for scoring
only after publication.

This is not a causal estimate, recession classifier, trading signal, or
financial-advice system.

## Run identity

| Field | Recorded value |
|---|---|
| Execution date and UTC time | `REPLACE` |
| Research cutoff | `2026-08-29` |
| Elixir Git head and dirty flag | `REPLACE` |
| Python Git head and dirty flag | `REPLACE` |
| Contract SHA-256 | `REPLACE` |
| Source-bundle SHA-256 | `REPLACE` |
| Elixir manifest SHA-256 | `REPLACE` |
| Python manifest SHA-256 | `REPLACE` |
| Verifier result | `MATCH` or exact failure |

Do not publish a final run record from a dirty checkout. If a diagnostic run
was dirty, preserve that fact and label the record incomplete.

## Source evidence

| Source | Observation boundary | Release boundary | Receipt count | Missing or rejected material |
|---|---|---|---:|---|
| BLS QCEW | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` |
| BEA Regional Accounts | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` |
| FHFA HPI reports | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` |

Record the preserved source-bundle location outside Git, Poppler version,
FHFA layout eras, manually sampled states, source notices, and any publication
whose release date or values could not be established.

## Environment

| Implementation | Runtime and package versions | Platform |
|---|---|---|
| Elixir | `REPLACE` | `REPLACE` |
| Python | `REPLACE` | `REPLACE` |

State whether dependency retrieval, dependency audits, formatting, tests,
Livebook verification, Python linting, typing, tests, build, notebook
validation, and dependency audits passed at the recorded heads.

## Eligibility and integrity

| Check | Observed result |
|---|---|
| States and DC in every admitted vintage | `REPLACE` |
| First and last emitted outer origins | `REPLACE` |
| Distinct eligible outer origins | `REPLACE` |
| Post-origin feature count | `0` or explain failure |
| Training labels unavailable at origin | `0` or explain failure |
| Elixir-Python panel bytes | `MATCH` or hashes |
| Elixir-Python fold bytes | `MATCH` or hashes |
| Deterministic prediction tolerance | `PASS` or maximum difference |
| Neural structural parity | `PASS`, `NOT ELIGIBLE`, or failure |

## Overall results

Primary metric: pooled MAE across all eligible state-origin forecasts.

| Model | Rows | MAE | RMSE | Median absolute error | Bias | Empirical 80 percent coverage |
|---|---:|---:|---:|---:|---:|---:|
| Zero growth | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` |
| Latest QCEW year-over-year | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` |
| Pooled ridge | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` |
| Equal weight | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` |
| Inverse MAE | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` |
| Convex stack | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` |
| Neural gate | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` | `REPLACE` |

Add the four individual expert rows. Report `NOT ELIGIBLE` instead of
manufacturing a neural result when the gate lacks eight out-of-fold quarters.

## Grouped results and ablations

Summarize results by forecast origin, state, and Census division. Name the
worst errors and periods with weak interval coverage. Report expert ablations,
equal weighting, and validation-error weighting on the same eligible rows.

Do not change model selection, eligibility, or reported groups after observing
test outcomes. Report a negative result directly if the ensemble does not beat
the naive baselines.

## Interpretation

State only conclusions supported by this run. Include exact dates, target,
population, metric, and revision policy in every performance statement.
Explain expert weights as predictive reliance within this fitted system, not
causal importance. Explain that empirical interval coverage is a historical
diagnostic, not a guaranteed probability for a future state outcome.

## Deviations, limitations, and unresolved evidence

- `REPLACE`: source or release deviations.
- `REPLACE`: missing observations or rejected layouts.
- `REPLACE`: implementation or environment deviations.
- `REPLACE`: model failures, non-finite values, or eligibility changes.
- `REPLACE`: material differences between Elixir and Python.

## Reproduction

Link the exact contract and source records, then record the commands used for
source admission, both model runners, and the no-write verifier. Reference
ignored evidence by hashes and custody location; do not commit publisher bytes,
panels, predictions, fitted state, credentials, or machine-specific paths.
