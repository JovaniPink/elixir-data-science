# Interpreting regional ensemble results

Checked against the v1 artifact contract on August 30, 2026.

## Start with run identity

Before reading a metric, confirm that the run record names the exact forecast
origins, 51-state/DC population, QCEW target, revision policy, contract hash,
source-bundle hash, Git heads, and verifier result. A result without that
identity cannot be compared safely with another run.

The August 29, 2026 `MATCH` result used synthetic data. It is replication
evidence, not evidence that a model forecasts real employment well.

## Read one prediction row

Each row answers one state, origin, and model question. `prediction` and
`final_outcome` use log-growth points:

```text
error = prediction - final_outcome
```

A positive error means the model predicted more growth than the final QCEW
outcome. A negative error means it predicted less. The target is close to a
percentage growth rate for small changes, but it is specifically
`100 * natural-log growth`, not ordinary percent change.

## Compare models on identical rows

Use the same eligible state-origin rows for every comparison. Do not compare a
neural result from fewer origins with a baseline from more origins without
showing the different population.

| Metric | What it answers | Important limit |
|---|---|---|
| MAE | Average absolute miss in log-growth points | Treats all errors linearly |
| RMSE | Error measure that penalizes large misses more heavily | Can be dominated by a few extreme rows |
| Median absolute error | Typical absolute miss | Can hide a harmful tail |
| Bias | Average signed error | Positive and negative misses can cancel |
| Empirical 80 percent coverage | Share of final outcomes inside historical residual intervals | Does not guarantee future 80 percent probability |
| Row count | Number of state-origin predictions | Must accompany every grouped metric |

Pooled MAE across all eligible state-origin rows is the primary result. State,
quarter, and Census-division tables are secondary diagnostics, not alternate
metrics to select after seeing the outcome.

## Read expert weights and contributions

A weighted model emits four nonnegative weights that sum to one:

```text
prediction = labor contribution
           + business contribution
           + growth contribution
           + housing contribution

expert contribution = expert prediction * expert weight
```

A positive weight can produce a negative contribution when that expert predicts
negative growth. Weight size shows reliance inside this fitted prediction. It
does not measure economic importance, causal effect, data quality, or policy
impact.

The four individual expert rows use one-hot weights. Equal weighting always
uses `0.25` for each expert. The convex stack uses one fixed selected vector for
an outer origin. The neural gate can vary weights by state and quarter context.

`zero`, `latest_qcew_yoy`, and `pooled_ridge` are not weighted combinations of
the four expert predictions, so their weight and contribution fields are blank.

## Read intervals carefully

The lower and upper fields place a symmetric historical residual radius around
the prediction. Coverage below 0.80 means outcomes fell outside that band more
often than the nominal historical target. Coverage above 0.80 does not prove
the interval is well calibrated; it may simply be wide.

Inspect interval width and coverage together. Also examine coverage by origin
and state, because pooled coverage can conceal concentrated failures.

## Diagnose grouped results

- By forecast origin: identifies quarters when all states became harder to
  predict or a national shock affected the panel.
- By state: identifies persistent geographic error, but contains relatively
  few evaluation quarters per state.
- By Census division: summarizes broader geographic patterns without treating
  neighboring states as independent proof.
- By model: shows whether added complexity improves the same target rows.

Do not label a difficult quarter a recession regime or a state difference a
structural cause without a separate study.

## Judge whether the ensemble helped

Use this order:

1. Confirm source integrity, fold eligibility, and cross-language verification.
2. Compare the convex stack with zero growth and latest QCEW growth.
3. Compare it with pooled ridge and equal weighting.
4. Inspect inverse-MAE weighting and expert ablations.
5. Compare the neural gate only on the origins where it is eligible.
6. Review large errors, bias, interval coverage, and grouped weaknesses.

Success means the evidence and replication contracts passed. It does not
require the ensemble to beat a baseline. If a baseline wins, report that result
without changing the model, test window, or primary metric after inspection.

## Safe performance language

A complete statement follows this pattern:

> In a point-in-time historical backtest covering [origins], the [model]
> predicted next-quarter final QCEW third-month employment year-over-year log
> growth for the 50 states and Washington, DC with [metric and value], using
> only releases available at each calendar quarter-end and final QCEW outcomes
> for scoring after publication.

Do not shorten that to "predicts state employment," "detects recessions," or
"finds the economic driver." Those claims exceed the experiment.
