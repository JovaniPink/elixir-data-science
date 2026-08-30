# Regional expert ensemble v1 artifact reference

Checked against both implementations and the shared contract on August 30,
2026.

## Serialization contract

All generated files are ignored. CSV files use UTF-8, a header, LF line
endings, one final LF, fixed column order, and decimal floats with 10 digits
after the decimal point. JSON uses sorted keys, compact encoding, and one final
LF. State rows follow the contract's two-character FIPS order.

The Elixir and Python repositories must contain byte-identical
`regional-expert-ensemble.v1` contract files. Each manifest records the hash of
those exact bytes.

## Source bundle

`regional-source-bundle.v1.json` is the admitted input authority.

| Section | Meaning |
|---|---|
| `schema_version` | Exactly `regional-source-bundle.v1` |
| `contract_sha256` | SHA-256 of the committed model contract |
| `research_cutoff` | Exactly `2026-08-29` in v1 |
| `sources` | One or more receipt objects covering QCEW, BEA, and FHFA |
| `observations` | Normalized `qcew`, `bea`, and `fhfa` row arrays |
| `extraction_tools.pdftotext` | Complete Poppler extraction version string |
| `fhfa_layout_checks` | One manual extraction record per admitted report URL |

Receipt and observation fields are defined in the source-admission runbook and
the three regional source records. The admitted builder also emits:

- `qcew-vintages.v1.csv`: `state_fips`, `observation_quarter`, `release_date`,
  `vintage`, `status`, `employment`, `establishments`, `total_wages`.
- `bea-vintages.v1.csv`: `state_fips`, `observation_quarter`, `release_date`,
  `vintage`, `real_gdp`, `personal_income`.
- `fhfa-vintages.v1.csv`: `state_fips`, `observation_quarter`, `release_date`,
  `report_url`, `hpi_qoq`, `hpi_yoy`.

## Regional panel

`regional-panel.v1.csv` contains one state row for every source-history and
evaluation origin from 2017 Q1 through 2025 Q3. Features use the latest
admitted observation available by the origin's calendar quarter-end.

| Fields | Meaning |
|---|---|
| `forecast_origin` | Calendar quarter-end at which the forecast is formed |
| `state_fips` | Two-character state/DC FIPS |
| `target_quarter` | Quarter immediately after the forecast origin |
| `target_quarter_number` | Integer 1 through 4 for the target quarter |
| `census_division` | Contract-defined Census division |
| `evaluation_origin` | `true` only for 2020 Q1 through 2025 Q3 |
| `qcew_employment_yoy` | `100 * ln(latest employment / employment four observation quarters earlier)` |
| `qcew_employment_qoq` | `100 * ln(latest employment / prior-quarter employment)` |
| `qcew_employment_yoy_lag1` | Prior observation quarter's year-over-year employment growth |
| `qcew_establishments_yoy` | Year-over-year QCEW establishment log growth |
| `qcew_total_wages_yoy` | Year-over-year QCEW total-wage log growth |
| `bea_real_gdp_yoy`, `bea_real_gdp_qoq` | BEA real GDP log growth from the selected archive |
| `bea_personal_income_yoy`, `bea_personal_income_qoq` | BEA personal-income log growth from the selected archive |
| `fhfa_hpi_qoq`, `fhfa_hpi_yoy` | Published FHFA percentage changes; no additional log transform |
| `qcew_release_date`, `bea_release_date`, `fhfa_release_date` | Latest release date used by that source's feature calculation |
| `target_employment_growth_yoy` | Final QCEW target used for later scoring |
| `outcome_available_date` | Latest final-publication date needed to know the target |
| `target_vintage` | Final QCEW target publication identifier |

The presence of a final target in the panel does not make it eligible for
training. Fold construction uses `outcome_available_date` to prevent early use.

## Expanding folds

`regional-folds.v1.csv` contains:

| Field | Meaning |
|---|---|
| `outer_origin` | Evaluation origin whose next-quarter target is forecast |
| `membership` | Exactly `train` or `forecast` |
| `row_origin` | Panel origin assigned to the fold |
| `state_fips` | State/DC FIPS |
| `target_quarter` | Target quarter for the panel row |
| `outcome_available_date` | Final target availability used for eligibility |

Training rows must precede `outer_origin`, and their outcomes must be public by
that origin's quarter-end. A fold is emitted only when at least eight distinct
training quarters are eligible. Forecast rows cover the outer origin's 51
states and DC entries.

## Predictions

`regional-predictions.v1.csv` is keyed by `forecast_origin`, `state_fips`, and
`model_id`.

| Field | Meaning |
|---|---|
| `target_quarter`, `census_division` | Forecast context copied from the panel |
| `prediction` | Predicted target in percentage points of log growth |
| `final_outcome` | Final QCEW target used for scoring |
| `error` | `prediction - final_outcome`; positive means overprediction |
| `interval_lower_80`, `interval_upper_80` | Prediction plus/minus the model's trailing empirical absolute-residual radius |
| `weight_labor`, `weight_business`, `weight_growth`, `weight_housing` | Expert weights for weighted models |
| `contribution_*` | Expert prediction multiplied by its corresponding weight |
| `alpha` | Selected ridge penalty for expert and pooled ridge rows; blank otherwise |

Model identifiers are `labor`, `business`, `growth`, `housing`, `zero`,
`latest_qcew_yoy`, `pooled_ridge`, `equal_weight`, `inverse_mae`,
`convex_stack`, and, when eligible, `neural_gate`.

The four expert rows use one-hot weights. Equal, inverse-MAE, convex, and neural
rows use nonnegative weights that sum to one. `zero`, `latest_qcew_yoy`, and
`pooled_ridge` leave weights and contributions blank. Every populated set of
contributions must sum to the prediction within `1.0e-6`.

## Run manifest

`regional-run-manifest.v1.json` contains:

| Section | Meaning |
|---|---|
| `schema_version` | Exactly `regional-run-manifest.v1` |
| `contract_sha256` | Exact shared contract hash |
| `source_bundle_sha256` | Hash of the exact admitted input bytes |
| `artifacts` | SHA-256, byte count, and data-row count for each CSV |
| `environment` | Implementation and language-specific runtime versions |
| `git` | Forty-character Git head, dirty flag, and executable path |
| `settings` | Ridge, stack, neural gate, and interval contract sections |
| `metrics` | Overall and grouped evaluation results |
| `exclusions` | Explicit v1 non-goals copied from the contract |
| `claims` | Point-in-time and prohibited-claim flags copied from the contract |

Metric groups are `overall`, `by_forecast_origin`, `by_state`, and
`by_census_division`. Each model reports MAE, RMSE, median absolute error, bias,
empirical 80 percent interval coverage, and row count.

## Cross-language verification

The verifier requires byte-identical panel and fold files, exact categorical
fields, exact convex-stack weights, and matching contract, source-bundle,
settings, exclusions, and claim evidence. Deterministic predictions,
contributions, alpha values, and metrics use an absolute tolerance of
`1.0e-6`.

Neural results are not expected to be numerically identical. Both sides must
emit the same eligible keys and final outcomes; predictions and intervals must
be finite; weights must lie in `[0,1]` and sum to one; contributions must sum to
the prediction; and alpha must be blank.
