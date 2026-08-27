# BLS QCEW Open Data source record

_Source, rights, and layout pages reviewed August 27, 2026._

## Decision

The comparison experiment retrieves one first-party U.S. Bureau of Labor
Statistics (BLS) Quarterly Census of Employment and Wages (QCEW) CSV slice:

| Field | Fixed value |
|---|---|
| Publisher | U.S. Bureau of Labor Statistics |
| Dataset | Quarterly Census of Employment and Wages |
| Period | First quarter 2024 |
| Slice | All industries, industry code `10` |
| Source URL | <https://data.bls.gov/cew/data/api/2024/1/industry/10.csv> |
| Media type | CSV, recorded as `text/csv` in the result manifest |
| Retrieval date | Recorded from the UTC download time in the generated source metadata and result manifest |

The [QCEW Open Data guide](https://www.bls.gov/cew/additional-resources/open-data/home.htm)
describes the CSV slices as published data intended for third-party programmers,
developers, and organizations. The
[slice documentation](https://www.bls.gov/cew/additional-resources/open-data/csv-data-slices.htm)
documents the URL structure and quarterly fields. The fixed URL is the guide's
documented all-industries pattern with an explicit 2024 first-quarter boundary.

The download is stored under `data/qcew/` with a sidecar containing its source
URL, UTC retrieval time, byte count, and SHA-256 hash. Both are generated and
ignored by Git. A later run reuses the local file only after its bytes match the
sidecar. `--refresh-source` makes a new retrieval and records new provenance.
QCEW values can be revised, so a matching implementation must use the exact
source hash recorded in the manifest rather than assume a later response has
identical bytes.

## Copyright, terms, and permitted use

The reviewed BLS
[copyright statement](https://www.bls.gov/opub/copyright-information.htm)
says BLS-published material is public domain, except for previously copyrighted
photographs and illustrations, and may be used without specific permission.
BLS asks users to cite BLS as the source. The QCEW CSV contains published data,
not third-party photographs or illustrations. No separate named data license
was identified; this source record labels its copyright status as public domain
and also preserves the BLS terms that govern access to BLS.gov.

The reviewed [BLS terms](https://www.bls.gov/developers/termsOfService.htm)
state that data accessed through BLS.gov should not include controls on end use.
They require a retrieval date and the following statement for public API users:

> BLS.gov cannot vouch for the data or analyses derived from these data after
> the data have been retrieved from BLS.gov.

The terms also prohibit presenting modified material as BLS content and do not
authorize use of the BLS logo. Under this bounded experiment, permitted use is
to retrieve the public CSV, compute a clearly labeled repository-derived
grouping, retain source attribution and retrieval metadata, and compare
independent implementations. This is an engineering summary of the reviewed
source terms, not legal advice. Recheck the source pages before a materially
different use.

## Selection and transformation

The experiment reads identifiers as strings and measures as signed 64-bit
integers. It trims identifier whitespace, then selects rows matching every
condition below:

| Column | Required value | Meaning |
|---|---|---|
| `year` | `2024` | Fixed comparison year |
| `qtr` | `1` | Fixed comparison quarter |
| `industry_code` | `10` | Total, all industries |
| `own_code` | `0` | Total covered, all ownerships |
| `size_code` | `0` | All establishment sizes |
| `agglvl_code` | `70` | County, total covered |
| `disclosure_code` | blank | Published, not marked as undisclosed |

The [QCEW aggregation-level table](https://www.bls.gov/cew/classifications/aggregation/agg-level-titles.htm)
defines code `70` as county, total covered. The
[quarterly field layout](https://www.bls.gov/cew/about-data/downloadable-file-layouts/quarterly/naics-based-quarterly-layout.htm)
defines the establishment, monthly employment, quarterly wage, and disclosure
fields used here.

The pipeline fails if the selection is empty, if a selected row has a nonblank
disclosure code, if a selected county FIPS is not a unique five-digit string,
or if a selected integer measure is missing. It derives `state_fips` from the
first two characters of the five-character county FIPS, groups by that key, and
emits these integer columns:

1. `state_fips`
2. `county_rows`
3. `qtrly_estabs`
4. `month1_emplvl`
5. `month2_emplvl`
6. `month3_emplvl`
7. `total_qtrly_wages`

Rows are sorted by `state_fips` ascending and serialized as UTF-8 CSV with a
header, LF line endings, and a final newline. The result is a derived
engineering artifact. It is not represented as an official BLS table.

## Claim boundary

The experiment checks whether two implementations can produce the same
deterministic grouped bytes and records their local resource measurements. It
does not explain why employment or wages have any value, estimate an effect,
predict a future condition, identify a recession, recommend a transaction, or
provide financial advice. QCEW concepts, revisions, disclosure controls, and
methodology remain governed by the linked BLS documentation.
