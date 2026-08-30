# Regional source admission and backtest runbook

Checked against the Elixir and Python implementations on August 30, 2026.

## Purpose and current boundary

This runbook moves an operator from preserved publisher files to paired,
ignored Elixir and Python backtest artifacts. It does not automate publisher
discovery or normalization.

`RegionalSourceBuilder` validates a candidate bundle that already contains
normalized QCEW, BEA, and FHFA observations. It optionally refreshes declared
publisher URLs only when the downloaded bytes match the receipt's existing
SHA-256 and byte count. It does not calculate new receipt hashes, parse QCEW or
BEA archives, extract FHFA tables, or approve PDF layouts.

No real publisher-backed bundle has passed this process yet. The August 29,
2026 cross-language result used synthetic source bytes.

## Prerequisites

- A supported Elixir and Erlang/OTP pair from the root README.
- The locked Elixir dependencies.
- The sibling Python repository with its locked environment.
- `pdftotext -layout` for FHFA reports, with the Poppler version recorded.
- Exact committed `regional-expert-ensemble.v1` contract bytes in both
  repositories.
- Publisher files and receipts stored below ignored `data/` paths.

Before normalization, read the three regional source records in
`docs/data-sources/`. Stop if a required release date, archived value, unit, or
FHFA layout cannot be established.

## Ignored working layout

Use this layout without committing any file below `data/` or `artifacts/`:

```text
data/regional/
  cache/                  exact publisher bytes and receipt sidecars
  candidate/
    regional-source-bundle.v1.json
  v1/                     admitted bundle and normalized CSV files
artifacts/regional-ensemble/
  elixir/v1/
  python/v1/
```

The candidate bundle is sensitive research evidence even when the underlying
publisher files are public. Preserve it outside Git with the source bytes.

## Prepare publisher receipts

Every receipt in `sources` requires:

| Field | Operator requirement |
|---|---|
| `source_id` | `qcew`, `bea`, or `fhfa`; at least one receipt for each source |
| `publisher_url` | Exact first-party URL on `bls.gov`, `bea.gov`, or `fhfa.gov` |
| `release_date` | Official public date in `YYYY-MM-DD` form, no later than 2026-08-29 |
| `retrieved_at` | UTC retrieval timestamp |
| `media_type` | Actual media type, such as `text/csv` or `application/pdf` |
| `sha256` | Lowercase SHA-256 of the exact cached bytes |
| `byte_count` | Positive byte count of the exact cached bytes |
| `terms_url` | Publisher policy reviewed for this retrieval |
| `vintage_status` | Plain description such as `archived_release` |
| `cache_path` | Readable ignored path to the exact bytes |

Do not use a retrieval timestamp, local modification time, or current API
response as a substitute for an official release date.

## Build the candidate bundle

The JSON root must contain:

```json
{
  "schema_version": "regional-source-bundle.v1",
  "contract_sha256": "sha256-of-exact-committed-contract",
  "research_cutoff": "2026-08-29",
  "extraction_tools": {"pdftotext": "complete-version-string"},
  "fhfa_layout_checks": [],
  "sources": [],
  "observations": {"qcew": [], "bea": [], "fhfa": []}
}
```

Populate normalized observations according to the source records and artifact
reference. Every source publication group must contain exactly the 51 state/DC
FIPS values in the shared contract. The candidate JSON may be formatted for
manual review; the admitted output will use canonical compact JSON.

For each distinct FHFA report URL, add one layout check containing:

- `report_url`, `release_date`, and a stable `layout_era` label;
- the same complete `pdftotext_version` stored under `extraction_tools`;
- `row_count` equal to 51; and
- `expected_headings`, `numeric_values`, `warning_text_preserved`, and
  `manual_samples_verified`, all set to `true` only after direct review.

## Admit the bundle

Default admission reads only local, hash-verified bytes:

```bash
mix run scripts/build_regional_source_bundle.exs \
  --candidate-bundle data/regional/candidate/regional-source-bundle.v1.json \
  --output-dir data/regional/v1
```

The output directory contains the canonical admitted bundle and normalized
`qcew-vintages.v1.csv`, `bea-vintages.v1.csv`, and
`fhfa-vintages.v1.csv` files.

Use `--refresh-source` only to confirm that publisher URLs still return the
already declared bytes. Refresh stages all downloads before writing, refuses
unmanaged existing cache targets, and fails if any byte count or hash differs.
It is not a command for accepting a new publisher revision.

## Run both implementations

Run Elixir from this repository:

```bash
mix run scripts/run_regional_expert_ensemble.exs \
  --source-bundle data/regional/v1/regional-source-bundle.v1.json \
  --output-dir artifacts/regional-ensemble/elixir/v1
```

Run Python from the sibling repository against the same admitted bundle bytes:

```bash
uv run --locked regional-expert-ensemble \
  --source-bundle /absolute/path/to/data/regional/v1/regional-source-bundle.v1.json \
  --output-dir artifacts/regional-ensemble/python/v1
```

Copying the source bundle is acceptable only when its SHA-256 is rechecked and
matches both run manifests.

## Verify and preserve evidence

Run the no-write verifier from the Elixir repository:

```bash
mix run scripts/verify_regional_expert_ensemble.exs \
  --elixir-dir artifacts/regional-ensemble/elixir/v1 \
  --python-dir /absolute/path/to/python-data-science/artifacts/regional-ensemble/python/v1
```

Before publishing a dated run record, preserve:

- the candidate and admitted bundle hashes;
- all source bytes and receipt sidecars;
- the three normalized vintage CSV files;
- both artifact directories and manifests;
- both exact Git heads and clean/dirty flags;
- the Poppler version and FHFA manual-review notes; and
- the verifier output.

## Failure guide

| Failure | Meaning | Required response |
|---|---|---|
| Wrong publisher host | Receipt or report URL is outside the admitted authority | Correct the source; do not override validation |
| Cache size or hash mismatch | Local or refreshed bytes differ from the receipt | Preserve both versions and create a new reviewed receipt |
| Incomplete 51-state/DC vintage | A publication group is missing or adds geography | Correct normalization or stop admission |
| Duplicate vintage key | Two normalized rows claim the same source identity | Resolve against the publisher bytes |
| Post-origin feature | A feature was not public at the forecast origin | Correct the release mapping; never move the date backward |
| Missing final QCEW outcome | The target cannot be scored under the contract | Add the authoritative final publication or remove the unsupported origin through a reviewed contract change |
| FHFA layout rejection | The report was not extracted or reviewed unambiguously | Add support for the layout era and repeat manual verification |
| `no_eligible_forecasts` | Fewer than eight eligible training quarters survived availability checks | Correct source coverage; do not weaken the fold rule ad hoc |
| Cross-language mismatch | Artifacts or contract meanings diverge | Preserve both outputs and resolve before reporting results |
