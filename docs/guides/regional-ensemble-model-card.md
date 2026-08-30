# Regional expert ensemble model card

Checked against the Elixir and Python implementations on August 30, 2026.

## Status

The ensemble is an executable research system with independently implemented
Elixir and Python pipelines. Both implementations passed the shared contract
using a complete synthetic multi-vintage bundle. No publisher-backed QCEW,
BEA, and FHFA bundle has completed the dated backtest, so there is no verified
real-world forecast-performance claim.

## Intended question

For each of the 50 states and Washington, DC, what next-quarter employment
growth would several specialist models predict using only information public by
the current calendar quarter-end?

The target is final QCEW third-month employment growth from the same quarter
one year earlier:

```text
100 * ln(final target-quarter employment /
         final employment four quarters earlier)
```

Forecast origins run from 2020 Q1 through 2025 Q3. Source history begins in
2017 Q1, and the research cutoff is August 29, 2026. Final target values are
used for scoring only after their final publication dates.

## Inputs and specialists

Each specialist is a ridge regression with deterministic state and target
quarter controls. Numeric features are standardized from its training rows
only.

| Expert | Features | Intended signal |
|---|---|---|
| Labor | QCEW employment year-over-year, quarter-over-quarter, and prior year-over-year growth | Recent state labor momentum |
| Business | QCEW establishment and total-wage year-over-year growth | Employer and payroll activity |
| Growth | BEA real GDP and personal-income year-over-year and quarter-over-quarter growth | State output and income momentum |
| Housing | FHFA published one-quarter and one-year HPI changes | Local housing-cycle conditions |

The features are predictive inputs, not causal variables. A housing expert
receiving a high weight does not prove that house prices caused employment to
change.

## Ridge training

For every outer forecast origin, training rows must come from earlier origins,
and their final outcomes must have been public by the outer origin's
quarter-end. At least eight distinct training quarters are required.

Each expert chooses its ridge penalty from `0.01`, `0.1`, `1`, `10`, and `100`
using expanding, time-ordered inner validation. A tie selects the larger
penalty. Ridge calculations use 64-bit inputs and a Cholesky solver in Scholar
and scikit-learn.

Ridge regression shrinks coefficients toward zero. That reduces unstable
responses when features overlap or the historical sample is small, while
remaining easier to inspect than a large neural model.

## Historical out-of-fold predictions

The system never trains a combiner directly on the same fitted expert values
that produced its inputs. It first walks through earlier quarters, repeatedly
fits each expert on still-earlier eligible rows, and predicts the held-out
quarter. These historical out-of-fold predictions become training data for the
weighting methods.

This time order is essential. Random row splitting could place later revisions
or outcomes in the training set for an earlier forecast.

## Comparators

The experiment reports four individual experts and these comparators:

| Model | Behavior |
|---|---|
| `zero` | Always predicts zero log growth |
| `latest_qcew_yoy` | Reuses the latest published QCEW employment year-over-year feature |
| `pooled_ridge` | Fits one ridge model using all expert features |
| `equal_weight` | Averages the four expert predictions |
| `inverse_mae` | Gives more weight to experts with lower historical out-of-fold MAE |

These models establish whether added ensemble complexity earns its place.

## Primary convex stack

The primary stack searches every nonnegative four-expert weight vector in
increments of `0.05` that sums to one. It selects the vector with the lowest
mean squared error on eligible historical out-of-fold predictions. Exact ties
use the contract's expert order: labor, business, growth, then housing.

The stack is transparent because every forecast includes its four weights and
the four products of expert prediction times weight. Those contributions sum
to the final prediction.

## Neural challenger

The challenger learns different expert weights from context. Its inputs are:

- four expert predictions;
- four trailing expert MAEs;
- four target-quarter indicators; and
- Census-division indicators.

A 16-unit `tanh` hidden layer produces four softmax weights. Softmax keeps each
weight between zero and one and makes the four weights sum to one. The forecast
is their weighted sum of the expert predictions.

Training uses seed 42, Adam with learning rate `0.01`, at most 500 epochs, the
latest four eligible quarters for validation, and patience 30. The challenger
runs only with at least eight out-of-fold quarters.

Elixir and Python neural training need structural, not numeric, parity. Their
eligible rows and final outcomes must match; predictions must be finite; and
weights and contributions must satisfy the shared invariants. Neural weights
can differ because the runtimes and numerical paths differ.

## Uncertainty and evaluation

Every model receives a symmetric empirical interval. The radius is the nearest
rank 80th percentile of that model's trailing absolute out-of-fold residuals.
The interval is:

```text
[prediction - radius, prediction + radius]
```

The primary metric is MAE pooled across eligible state-origin rows. The
manifest also reports RMSE, median absolute error, bias, empirical interval
coverage, and row count overall and by forecast origin, state, and Census
division.

These intervals describe historical residual behavior. They are not calibrated
probability guarantees for an individual future state forecast.

## Appropriate and inappropriate uses

Appropriate uses include testing point-in-time data engineering, comparing
transparent ensemble methods, studying when experts receive different weights,
and reproducing results across Elixir and Python.

Do not use the system to claim causality, classify recessions, recommend a
trade, provide financial advice, or describe a synthetic verification as real
economic performance. Any performance statement must say "point-in-time
historical backtest" and name the dates, target, population, metric, and
revision policy.

## Material limitations

- A real publisher-backed run has not been completed.
- QCEW, BEA, and FHFA revise history, so source-release mapping is part of the
  model rather than a clerical detail.
- State-level pooling can hide local industry and county differences.
- The 2020-2025 evaluation window is short and includes unusual economic
  disruption.
- Expert weights may be unstable when experts make similar predictions.
- Good historical error does not establish future stability.
- The neural gate is a challenger, not the primary reporting model.
