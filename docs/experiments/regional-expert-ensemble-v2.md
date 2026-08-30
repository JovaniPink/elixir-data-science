# Publisher-Backed Regional Expert Ensemble v2

Reviewed August 30, 2026.

## Status

This document describes a versioned implementation contract and current source
admission evidence. It is not a publisher-backed forecast result.

The verified v1 Elixir and Python comparison used synthetic data. Version 2
preserves every v1 byte and introduces typed source boundaries, indexed
artifacts, admission profiles, a screened convex stack, and a dynamic neural
gate. A real QCEW, BEA, and FHFA bundle has not passed admission.

## Material finding from the real QCEW file

The official BLS state revision CSV retrieved on August 30, 2026 contains
revision history beginning in 2017. The local ignored receipt recorded:

- 991,632 bytes;
- SHA-256
  `0953b060e139bcba235652547a4f9d204543cbe06253501ddff17d6a84767ea7`;
- 9,990 data rows plus one header;
- observation years 2017 through 2026; and
- revision fields for establishments, each employment month, and total wages.

The immutable v1 contract starts panel construction at 2017 Q1. No 2017 Q1
QCEW observation was public by March 31, 2017, and the feature lags require
pre-2017 observations that the state revision file does not contain. The
synthetic fixture starts in 2015, so it did not expose this conflict.

Version 2 does not backfill those periods with mutable current history. It
records 2020 Q1 as the requested evaluation start and derives the effective
start from complete point-in-time features and published labels. A bounded
release-timing fixture independently derives:

- 2018 Q4 as the first complete QCEW feature origin; and
- 2021 Q1 as the first outer origin with eight fully published prior labels.

Those dates are regression evidence, not yet a final real-bundle result. The
real bundle must reproduce every state, release, and outcome date before the
dates can be published as an executed backtest range.

## Active profiles

| Profile | Experts | Status |
|---|---|---|
| `core` | Labor, QCEW business, BEA growth, FHFA housing | Contracted; real bundle incomplete |
| `leading_signals` | Core plus QCEW industry, Census BFS, and building permits | Implemented as a contract; sources not admitted |
| `energy_prospective` | EIA electricity | Inactive |
| `labor_flows_candidate` | Census QWI | Inactive |
| `credit_candidate` | FDIC bank health | Inactive |

Treasury yields are gate context for `leading_signals`, not a state expert.

## Modeling changes

The classical experts remain ridge regressions with float64 inputs,
training-only standardization, expanding validation, the fixed alpha grid, and
larger-alpha tie breaking.

The primary v2 combiner is `screened_convex_stack`:

1. Rank active experts using only prior out-of-fold MAE.
2. Resolve ranking ties using contract expert order.
3. Select at most four experts.
4. Search every nonnegative weight vector in 0.05 increments that sums to one.
5. Minimize prior out-of-fold MSE.
6. Emit exact zero weights for unselected experts.

The challenger remains one 16-unit `tanh` layer followed by softmax weights.
Its output width now follows the active profile instead of being fixed at four.
Treasury and declared exposure variables may enter its context. Neural parity
across languages remains structural rather than numeric.

## Evidence boundary

Success means source admission, reproducible artifacts, temporal validation,
and cross-language verification pass. It does not require a model to beat a
baseline. Every performance statement must use the phrase "point-in-time
historical backtest" and identify the dates, target, population, metric, and
revision policy.

No causal result, recession classification, trading signal, financial advice,
live serving, or deployment belongs to this experiment.
