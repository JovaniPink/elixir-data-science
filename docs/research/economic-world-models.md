# Economic World Models as a Separate Research Track

Reviewed August 30, 2026.

## Boundary

An economic world model represents agents, institutions, state transitions,
and feedback over multiple steps. That is a different research object from the
regional one-quarter forecasting ensemble. The two tracks must not share model
artifacts or claims.

The repositories
[Awesome Machine Learning in Economics and Finance](https://github.com/cwyalpha/Awesome-Machine-Learning-in-Economics-and-Finance)
and
[Awesome Economic World Models](https://github.com/FreedomIntelligence/Awesome-Economic-World-Models)
were reviewed as inspiration catalogs. No recognized license was present in
the August 30, 2026 review, so this note does not copy their collections.

## Proposed research contract

Define agents such as households, employers, banks, and governments; the
institutions and constraints they face; observable and latent state; allowed
actions; transition rules; shocks; and the outputs to evaluate. State which
rules are estimated, calibrated, assumed, or learned.

Evaluation must separate:

- one-step predictive accuracy;
- multi-step stability and error growth;
- accounting and institutional consistency;
- reproduction of prespecified historical moments;
- behavior under held-out shocks;
- sensitivity to agent rules and calibration targets; and
- simulation-to-reality limits.

Plausible narratives or visually realistic rollouts are not validation.
Calibration to historical moments can reproduce the moments by construction.
Policy counterfactuals require credible behavioral invariance assumptions and
uncertainty analysis.

## First bounded experiment

Start with a synthetic state labor-market transition model. Represent employer
entry, hiring, separation, wage adjustment, and a national rate shock. Verify
mass balance, deterministic replay under a fixed seed, parameter recovery on
synthetic data, and multi-step error against a known simulator. Do not connect
that experiment to the real regional forecast report until a separate review
defines the relationship.
