# Regional Expert Ensemble v2 Artifact Reference

Reviewed August 30, 2026.

## Source bundle

`regional-source-bundle.v2.json` is an index. It does not embed observation
arrays. It records the exact v2 contract hash, profile, research cutoff,
publisher receipts, relative artifact paths, hashes, byte counts, row counts,
extraction tools, terms, and manual checks.

Only declared regular files below the bundle root are allowed. Admission
rejects absolute paths, path traversal, symlinks, undeclared files, byte or hash
mismatches, unknown releases, and data published after the research cutoff.

The declared normalized files are:

```text
normalized/qcew-state-vintages.v2.csv
normalized/qcew-industry-vintages.v2.csv
normalized/bea-vintages.v2.csv
normalized/fhfa-vintages.v2.csv
normalized/bfs-vintages.v2.csv
normalized/building-permits-vintages.v2.csv
normalized/treasury-daily.v2.csv
```

Elixir alone normalizes publisher bytes. Elixir and Python independently read
the same normalized bytes and construct downstream artifacts.

## Model artifacts

| Artifact | Purpose |
|---|---|
| `regional-panel.v2.csv` | Canonical state-origin features, source release dates, and final scoring target |
| `regional-folds.v2.csv` | Exact training and forecast membership with outcome availability |
| `regional-predictions.v2.csv` | Compact predictions, outcomes, errors, and empirical intervals |
| `regional-expert-contributions.v2.csv` | Long-form expert weight and contribution by origin, state, and model |
| `regional-model-index.v2.json` | Hashes of language-specific ridge, stack, and neural state |
| `regional-run-manifest.v2.json` | Contract, artifact, environment, Git, metric, exclusion, and claim evidence |

Generated source files, panels, predictions, model state, manifests, and
credentials remain in ignored directories.

## Cross-language rules

Panel and fold files must be byte-identical. Profiles, selected expert IDs, and
screened stack weights must be exact. Deterministic predictions and metrics
must agree within `1.0e-6`. Neural predictions need identical eligible folds,
finite values, weights in the closed interval from zero to one, and row weights
that sum to one within `1.0e-6`.
