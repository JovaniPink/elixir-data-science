# Contributing

This repository accepts small, reviewable Elixir data-science experiments and
their evidence. A contribution is complete only when its code, contracts,
tests, run instructions, source authority, and claim limits agree.

## Start safely

- Create a focused branch from a refreshed, recorded `main` revision.
- Use a separate worktree when the current checkout is dirty or concurrent work
  could overlap.
- Preserve unrelated changes and stage explicit files.
- Do not commit raw datasets, credentials, generated panels, predictions,
  fitted model state, or machine-specific paths.
- Keep generated work below ignored `data/`, `artifacts/`, or `exports/` paths.

Supported versions, pinned containers, and exact setup commands are maintained
in the root README, `.tool-versions`, `mix.exs`, `mix.lock`, and CI workflow.
Keep them synchronized when changing runtime support or dependencies.

## Experiment requirements

Every new or materially changed experiment must include:

1. A bounded research question, population, observation period, and output.
2. A source record for each external dataset, including publisher, URLs,
   checked date, fields, units, terms, permitted use, revisions, and limits.
3. A deterministic interface or versioned artifact contract when another
   implementation must reproduce the result.
4. Synthetic or otherwise redistributable fixtures for automated tests.
5. Exact run and verification commands that keep generated evidence outside
   Git.
6. A dated run record for observed results, separate from design documentation.
7. Explicit non-goals and language that matches the strength of the evidence.

Access to a dataset is not permission to train on, redistribute, or publish it.
Prefer first-party publishers and preserve exact source identity, retrieval
time, release date, hashes, byte counts, and relevant terms.

## Elixir quality

- Add `@spec` declarations and named types where they make public and internal
  contracts clearer.
- Preserve deterministic ordering, numeric types, seeds, and serialization
  rules when artifacts are compared across languages.
- Handle source, parsing, validation, and model failures explicitly. Do not
  convert missing or invalid economic data into silent defaults.
- Use expanding or otherwise time-ordered validation for forecasting work.
  Random row splits require separate justification.
- Keep source observations, transformations, model outputs, and interpretation
  visibly separate.

## Required validation

Run the repository-defined gates with the supported toolchain:

```bash
mix deps.get --check-locked
mix hex.audit
mix format --check-formatted
mix test
elixir scripts/verify_livebook_runtime.exs
```

Use the pinned container command in the README when local Elixir is unavailable.
Do not suppress a retired dependency or security advisory without a separately
reviewed justification.

Documentation changes must also pass `git diff --check`, use printable ASCII
and US English, resolve repository-relative links, and cite current primary
sources near material claims. A passing local link check does not prove an
external publisher page is still current.

## Cross-language changes

The regional ensemble contract is duplicated byte-for-byte in this repository
and the sibling Python repository. Any contract change requires coordinated
updates, independent panel and fold construction, both language-specific gate
suites, and the no-write Elixir verifier.

Do not describe parity from matching tests alone. Record the exact Git heads,
source-bundle hash, artifact receipts, eligible folds, verifier output, and any
neural structural-only comparison.

## Pull request checklist

- State scope and non-scope.
- Link source and contract evidence.
- List exact commands run and their results.
- Identify generated evidence and confirm it remains ignored.
- Describe risks, failure behavior, and rollback.
- Call out any manual source or layout review.
- Confirm the branch head and repository identity before merge.
- After merge, read back the remote merge state and required checks before
  reporting completion.

Descriptive clusters and predictive backtests are not causal explanations,
recession classifiers, trading systems, or financial advice. Report negative
results without changing the selection procedure after observing test outcomes.
