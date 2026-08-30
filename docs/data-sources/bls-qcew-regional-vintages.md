# BLS QCEW regional vintages source record

_Source, revision, rights, and layout pages checked August 30, 2026._

## Decision

The regional expert ensemble is designed to admit U.S. Bureau of Labor
Statistics Quarterly Census of Employment and Wages state totals for the 50
states and Washington, DC. Territories are excluded. The required slice is all
ownerships and all industries. The experiment uses employment for the third
month of each quarter, establishment counts, and total quarterly wages.

This record approves BLS as the source authority. It does not claim that a real
2017 Q1 through 2025 Q4 vintage bundle has been assembled. The dated synthetic
bundle remains the only admitted regional test input in this repository.

## Publisher evidence

- Publisher: U.S. Bureau of Labor Statistics
- Program: Quarterly Census of Employment and Wages
- Revision history: <https://www.bls.gov/cew/revisions/home.htm>
- Data source guide: <https://www.bls.gov/cew/about-data/data-files-guide.htm>
- Quarterly layout: <https://www.bls.gov/cew/about-data/downloadable-file-layouts/quarterly/naics-based-quarterly-layout.htm>
- Questions and limitations: <https://www.bls.gov/cew/questions-and-answers.htm>
- Copyright: <https://www.bls.gov/opub/copyright-information.htm>
- BLS terms: <https://www.bls.gov/developers/termsOfService.htm>

BLS says its downloadable files provide the full QCEW publication data and go
back to 1975. The Open Data collection covers the most recent five years, so it
cannot alone supply the complete historical boundary for this experiment.

BLS publishes national and state revision data from 2017 onward. Q1 values are
published five times, Q2 four times, Q3 three times, and Q4 twice. The revision
file is updated after each QCEW release. BLS also warns that unadjusted QCEW
data are revised and were not designed as a continuous time series.

## Point-in-time policy

For each state and observation quarter, preserve every reconstructable
publication with its actual public release date. At a forecast origin, select
the newest publication whose release date is on or before the calendar
quarter-end. A value's observation quarter is not its availability date.

The target is:

```text
100 * ln(final third-month employment for the target quarter /
         final third-month employment for the same quarter one year earlier)
```

Final employment is used only for scoring after its final publication date. It
must not replace the preliminary or revised history that a model would have
seen at an earlier origin.

## Normalized observations

Each admitted row in `observations.qcew` contains:

| Field | Meaning |
|---|---|
| `state_fips` | Two-character state or DC FIPS from the shared contract |
| `observation_quarter` | Canonical `YYYYQn` reference quarter |
| `release_date` | Date this exact value became public |
| `vintage` | Stable operator-assigned identifier for the publication |
| `status` | Exactly `preliminary` or `final` |
| `employment` | Third-month employment level, persons |
| `establishments` | Quarterly establishment count |
| `total_wages` | Total quarterly wages, dollars |

Employment, establishments, and wages must be positive finite levels. The
model derives year-over-year and quarter-over-quarter natural-log growth after
the point-in-time vintage is selected.

## Rights and attribution

BLS states that its published material is generally public domain, subject to
exceptions for third-party photographs and illustrations. The experiment must
cite BLS, record the retrieval date, avoid the BLS logo, and label every
transformation and forecast as repository-derived. BLS asks API users to state
that BLS cannot vouch for analyses derived after retrieval. This record is an
engineering summary, not legal advice; recheck the linked terms before a
materially different use.

## Admission checks and limits

- Record the publisher URL, release date, UTC retrieval time, media type,
  terms URL, SHA-256, byte count, vintage status, and ignored cache path.
- Require exactly 51 unique state/DC rows for every admitted publication.
- Reject territories, duplicate vintage keys, missing states, unknown release
  dates, future releases, nonpositive levels, and receipt-byte mismatches.
- Retain source notices and errata that affect a release.
- Do not infer a publication date from a file modification time or retrieval
  time.
- Stop real-data admission if the 2017-forward revision material cannot
  reconstruct the state employment values available at each required origin.
