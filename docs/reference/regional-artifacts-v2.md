# Regional Expert Ensemble v2 Artifact Reference

Reviewed September 23, 2026.

## Source bundle

`regional-source-bundle.v2.json` is an index. It does not embed observation
arrays. It records the exact v2 contract hash, profile, research cutoff,
publisher receipts, relative artifact paths, hashes, byte counts, row counts,
extraction tools, terms, and manual checks.

The v2 contract (`contracts/regional-expert-ensemble.v2.json`, `bundle.reject`)
declares that admission must reject absolute paths, path traversal, symlink
escapes, undeclared files, hash mismatches, unknown releases, and data published
after the research cutoff. Only part of that list is implemented.

Implemented in `ElixirDataScience.RegionalV2`, one declared receipt at a time:

- `artifact_receipt!/3` reads a file and records its path, SHA-256, byte count,
  and caller-supplied row count as an `ArtifactReceipt`.
- `validate_artifact/2` rejects absolute and traversing relative paths, symlinks
  in the file or any parent component, and non-regular files. It then reads the
  bytes and rejects a byte-count or SHA-256 mismatch.

Planned and not implemented for v2:

- parsing `regional-source-bundle.v2.json` or building `SourceReceipt` values
  from it;
- rejecting undeclared files under the bundle root;
- rejecting unknown releases; and
- enforcing the research cutoff against publication dates.

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

The local-only `economic-data-pipeline` repository owns v2 publisher-byte
custody and normalization. Neither model repository downloads or normalizes v2
publisher data. The existing v1 Elixir admission and normalization behavior is
unchanged.

In this repository, v2 Elixir code validates and reads those bytes only through
`validate_artifact/2` and `artifact_receipt!/3`. No v2 code parses the
normalized CSVs into `PublishedObservation` values, and none builds panels,
folds, predictions, model state, or run manifests from them.

`RegionalV2` also provides these building blocks, which are exercised only by
in-memory fixtures in `test/elixir_data_science/regional_v2_test.exs`:

- `load_contract/0`, `contract_sha256/0`, and `profile/1` or `profile/2` for
  contract and profile admission;
- `first_complete_quarter_origin/5`, `require_complete_quarter_origin/4`, and
  `first_eligible_outer_origin/2` for point-in-time eligibility over typed
  `PublishedObservation` and `PanelRow` values;
- `screened_convex_stack/4` for the screened stack; and
- `neural_gate_model/2`, which defines the Axon gate but does not train it.

The planned design has Elixir and Python independently read the same
normalized bytes and construct the model artifacts below. That pipeline is not
implemented.

## Model artifacts (planned)

No v2 code writes these files yet. The contract (`artifacts`) names them.

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

## Cross-language rules (planned)

These rules apply once both languages emit v2 artifacts. No v2 cross-language
verifier exists yet. Panel and fold files must be byte-identical. Profiles, selected expert IDs, and
screened stack weights must be exact. Deterministic predictions and metrics
must agree within `1.0e-6`. Neural predictions need identical eligible folds,
finite values, weights in the closed interval from zero to one, and row weights
that sum to one within `1.0e-6`.
