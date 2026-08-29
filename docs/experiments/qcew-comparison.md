# QCEW Elixir-Python comparison contract

_Experiment contract added August 27, 2026._

## Question

Can an Elixir and Explorer pipeline reproducibly download, validate, group, and
serialize one fixed QCEW slice so that an independent Python implementation can
match the result bytes, be verified field by field, and compare local execution
measurements?

This is a software and data-pipeline comparison. It does not make an economic,
causal, predictive, recession, trading, or financial claim.

## Run

From the repository root with the supported Elixir toolchain:

```bash
mix run scripts/run_qcew_comparison.exs
```

The default performs five timed transforms. The first is labeled
`cold_runtime`; the remaining four are labeled `warm_runtime`. Use a different
count, with a minimum of two, when needed:

```bash
mix run scripts/run_qcew_comparison.exs --iterations 10
```

To deliberately retrieve the BLS source again:

```bash
mix run scripts/run_qcew_comparison.exs --refresh-source
```

When the experiment runs inside a container or virtual machine, runtime-visible
hardware can differ from the physical host. Supply a sanitized host label when
that distinction matters:

```bash
mix run scripts/run_qcew_comparison.exs \
  --host-hardware-label "workstation-model" \
  --host-cpu-model "processor-model" \
  --host-logical-processors 12 \
  --host-memory-bytes 34359738368
```

These values are recorded as operator-provided metadata. Do not include a
serial number, hardware UUID, hostname, user name, or other unique identifier.

Generated files are written to ignored paths:

| Path | Purpose |
|---|---|
| `data/qcew/2024-q1-industry-10.csv` | Exact downloaded BLS bytes |
| `data/qcew/2024-q1-industry-10.csv.source-metadata.v1.json` | Source URL, retrieval time, byte count, and SHA-256 |
| `artifacts/qcew-comparison/v1/qcew-state-totals.v1.csv` | Canonical grouped result |
| `artifacts/qcew-comparison/v1/qcew-comparison-manifest.v1.json` | Versioned source, result, environment, and measurement record |

Do not commit these files. Keep the result manifest and its exact source file
together when transferring one run for an independent comparison.

## Version 1 result contract

The source, filters, disclosure rule, grouping key, integer aggregations, column
order, row order, and CSV serialization rules are defined in the
[QCEW source record](../data-sources/bls-qcew-open-data.md) and repeated in the
generated manifest. The manifest records:

- schema version and experiment ID;
- first-party publisher, dataset, source URL, retrieval time, byte count, and
  source SHA-256;
- copyright status, terms URL, permitted-use summary, and BLS disclaimer;
- exact transformation and serialization contract;
- result path, byte count, SHA-256, row counts, and integer totals;
- repository commit and dirty-worktree state;
- runtime-visible architecture, CPU model, logical processor count, available
  memory metadata, optional sanitized physical-host metadata, operating system,
  Elixir, OTP, ERTS, Explorer, and Jason versions; and
- one timing and peak-memory record for each iteration.

The manifest does not contain source CSV bytes. Source and result bytes remain
separate ignored artifacts.

## Verify a Python result

First run the Elixir experiment so the ignored reference CSV and manifest exist.
Then point the verifier at the Python-produced canonical CSV and version 1
manifest:

```bash
mix run scripts/verify_qcew_comparison.exs \
  --python-result /absolute/path/to/qcew-state-totals.v1.csv \
  --python-manifest /absolute/path/to/qcew-comparison-manifest.v1.json
```

The command uses the default Elixir artifact paths listed above. Use
`--elixir-result` and `--elixir-manifest` to compare a transferred reference
pair instead. The command reads all four files and writes nothing. A match exits
with status 0, a contract or value mismatch exits with status 1, and an unreadable
or invalid input exits with status 2.

The Python manifest must use `qcew-comparison-manifest.v1`, preserve the fixed
source, transformation, result-path, and claim fields, and record a nonempty
version at `environment.runtime.python`. It may record Python-specific benchmark,
repository, library, and environment fields. Those observations are not expected
to equal the Elixir run.

The verifier checks:

- the fixed schema version, experiment ID, source description, transformation,
  serialization, result path, and claim boundary;
- valid UTC manifest and source timestamps, plus the source URL, retrieval date,
  SHA-256, byte count, and media type against the Elixir reference manifest;
- each result file's actual SHA-256, byte count, row count, and integer totals
  against its own manifest;
- canonical UTF-8, LF-only bytes, the exact header and final newline, two-digit
  unique state FIPS values, ascending state order, and canonical signed 64-bit
  integers, including positive county counts and consistent row-count bounds; and
- exact state and column values across the Elixir and Python results.

Every difference is reported with a stable path plus the expected and actual
value. A Python CSV whose manifest hashes and totals were refreshed after a value
mutation still fails on the exact state and column. Benchmark timings, memory
samples, operating-system details, repository commits, and generation times are
not cross-run equality fields.

Because this command consumes result and manifest pairs, it verifies that both
manifests claim the same pinned source identity; it does not rehash or reprocess
the raw source CSV. Keep each manifest with its exact source file and run each
producer's source validation before using the cross-language result. Do not copy
generated files into tracked directories. Confirm the repository remains clean
with `git status --short` after the comparison.

## Measurement boundary

Each timed iteration includes Explorer CSV parsing, contract validation,
filtering, grouping, sorting, and in-memory CSV serialization. It excludes the
network download, source-cache verification, result and manifest writes, and
environment and Git inspection. A full BEAM garbage collection runs before
each timed transform and is outside the timed interval.

Timing uses the BEAM monotonic nanosecond clock. A sampler records process
resident-set size and `:erlang.memory(:total)` before and during each iteration.
The manifest reports the observed peak and peak-minus-start value for both.
Sampling overhead is included. BEAM-managed memory does not cover every native
allocation, so process RSS is the broader measurement. RSS is still sampled,
not a kernel-provided exact high-water mark.

The state labels have narrow meanings:

| Label | Meaning |
|---|---|
| `cold_runtime` | First timed transform in the current BEAM instance |
| `warm_runtime` | A later timed transform in the same BEAM instance |
| `downloaded_this_run` | The source file was retrieved before measurement in this run |
| `reused_verified_local_file` | Existing source bytes matched their sidecar before measurement |
| `filesystem_cache_state: uncontrolled` | The experiment did not flush or claim control of the operating-system page cache |

The labels do not claim a cold machine, cold disk, or isolated hardware. Compare
measurements only with the full environment and state metadata attached.

## Python production checklist

A Python implementation should:

1. require the exact source SHA-256 from the Elixir manifest;
2. read identifiers as strings and measures as signed 64-bit integers;
3. trim identifier and disclosure fields;
4. apply every version 1 filter and fail on an empty selection;
5. fail if a selected disclosure code is nonblank, a selected `area_fips` is
   not a unique five-digit string, or a selected measure is missing;
6. derive `state_fips` from the first two `area_fips` characters;
7. perform the same integer counts and sums;
8. use the same column order, state sort, CSV encoding, LF line endings, and
   final newline; and
9. emit `qcew-comparison-manifest.v1` with `environment.runtime.python`, the
   fixed source/result contract, and its observed result metadata; and
10. run the Elixir verifier and resolve every mismatch before comparing
    performance.

For timing, Python should use the same source bytes, iteration count, inclusion
boundary, state labels, pre-iteration garbage collection, RSS sampling
interval, and hardware. Runtime-specific
memory metrics may be added, but they are not interchangeable with
`:erlang.memory(:total)`. Matching bytes is a correctness cross-check; timing or
memory differences are observations from the recorded environments, not a
general language ranking.
