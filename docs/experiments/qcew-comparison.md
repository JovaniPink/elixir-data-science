# QCEW Elixir-Python comparison contract

_Experiment contract added August 27, 2026._

## Question

Can an Elixir and Explorer pipeline reproducibly download, validate, group, and
serialize one fixed QCEW slice so that an independent Python implementation can
later match the result bytes and compare local execution measurements?

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

## Python matching checklist

A later Python implementation should:

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
9. compare the result SHA-256 and integer totals before comparing performance.

For timing, Python should use the same source bytes, iteration count, inclusion
boundary, state labels, pre-iteration garbage collection, RSS sampling
interval, and hardware. Runtime-specific
memory metrics may be added, but they are not interchangeable with
`:erlang.memory(:total)`. Matching bytes is a correctness cross-check; timing or
memory differences are observations from the recorded environments, not a
general language ranking.
