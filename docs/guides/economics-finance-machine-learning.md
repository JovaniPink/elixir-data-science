# Economics and Finance Machine Learning Guide

Reviewed August 30, 2026.

## Start with the claim

Prediction, causal inference, structural estimation, and simulation answer
different questions. A forecasting model can estimate a future outcome without
identifying why it changes. A causal estimate needs a credible identification
design. A structural or world model needs explicit behavioral assumptions and
separate calibration evidence.

For this repository, the regional ensemble is predictive. It does not estimate
policy effects, declare recessions, produce trading signals, or provide
financial advice.

## Temporal validation

- Join values using the date they became public, not only their observation
  period.
- Use expanding training windows and later validation quarters.
- Standardize numeric features using training rows only.
- Generate historical out-of-fold expert predictions before training a stack
  or gate.
- Keep final revised outcomes for scoring only after their publication date.
- Preserve source vintages so a later revision cannot silently change an old
  fold.

Random row splits are not an acceptable substitute for this contract. State
rows in the same quarter share national conditions and publication history.

## Model design

Use transparent controls and baselines first. Ridge regression is useful here
because correlated economic features are expected, samples are modest, and the
regularization path can be prespecified. Compare every ensemble with zero
growth, the latest published QCEW growth, a pooled ridge, equal weights, and
inverse-MAE weights.

A mixture of experts is useful only when specialists have different error
patterns. Inspect expert ablations, weights, and contributions. A context gate
may use state exposure and national rates, but national variables repeated for
all states are not independent state evidence.

## Leakage review

Check for revised current-history downloads, labels published after the outer
origin, statistics standardized on the full sample, same-quarter residuals in
trailing errors, future classification codes, backfilled release dates, and
feature selection changed after viewing test results.

## Evaluation

Primary reporting uses pooled MAE. Also report RMSE, median absolute error,
bias, empirical 80 percent interval coverage, and results by origin, state, and
Census division. Report source and expert ablations. Preserve negative and null
results without changing the prespecified model.

Good agreement between Elixir and Python demonstrates contract replication.
It does not prove economic usefulness. Beating one baseline does not establish
causality, stability in future periods, or investment value.
