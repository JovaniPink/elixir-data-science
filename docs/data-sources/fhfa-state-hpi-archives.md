# FHFA state HPI archives source record

_Source, report, methodology, revision, and rights pages checked August 30,
2026._

## Decision

The regional expert ensemble is designed to admit the seasonally adjusted,
purchase-only Federal Housing Finance Agency House Price Index one-quarter and
one-year percentage changes for the 50 states and Washington, DC. Historical
folds use the official quarterly report available at the forecast origin, not
the mutable current download.

This record approves archived FHFA quarterly reports as the point-in-time
authority. It does not claim that every required report layout has passed
manual extraction review.

## Publisher evidence

- Publisher: Federal Housing Finance Agency
- HPI datasets: <https://www.fhfa.gov/house-price-index?tab=HPI+Datasets>
- HPI questions and methodology: <https://www.fhfa.gov/faqs/hpi>
- Historical report example: <https://www.fhfa.gov/reports/house-price-index/2019/Q4>
- HPI technical description: <https://www.fhfa.gov/research/papers/house-price-indexes-hpi-technical-description>
- Website copyright and attribution policy: <https://www.fhfa.gov/about/fhfa-policies/website-privacy-policy>

FHFA describes the flagship HPI as a purchase-only, seasonally adjusted
repeat-sales index. It measures average changes for single-family properties
with conforming conventional mortgages purchased or securitized by Fannie Mae
or Freddie Mac. Quarterly reports add state coverage and publish one-quarter
and one-year percentage changes.

FHFA updates historical estimates as new and seasoned mortgages arrive. The
current downloadable series therefore contains information that was not
available at earlier forecast origins. An archived report page records the
publication date and links the corresponding report attachment.

## Point-in-time extraction policy

For every admitted report:

1. Download the official report attachment and retain its exact bytes under an
   ignored path.
2. Record the report page URL, attachment URL, publication date, retrieval
   time, media type, SHA-256, byte count, and terms URL.
3. Run `pdftotext -layout` and record the complete Poppler version string.
4. Extract only the seasonally adjusted purchase-only state table's one-quarter
   and one-year percentage changes.
5. Identify a layout era and manually compare sampled states against the
   rendered report before admitting any report from that era.

The normalized values are already percentage changes. Do not apply the
natural-log transformation used for positive QCEW and BEA levels.

## Normalized observations

Each admitted row in `observations.fhfa` contains:

| Field | Meaning |
|---|---|
| `state_fips` | Two-character state or DC FIPS from the shared contract |
| `observation_quarter` | Reported HPI reference quarter in `YYYYQn` form |
| `release_date` | Official quarterly report publication date |
| `report_url` | Official `fhfa.gov` historical report URL |
| `hpi_qoq` | Published one-quarter percentage change |
| `hpi_yoy` | Published one-year percentage change |

Each report also requires a matching `fhfa_layout_checks` entry with its
release date, layout era, Poppler version, row count, and affirmative checks for
expected headings, numeric values, preserved warning text, and manual samples.

## Rights and attribution

FHFA states that information produced by federal agencies is generally public
domain, while seals, trademarks, and some third-party material are protected.
Do not reproduce the FHFA seal or imply endorsement. FHFA requires services
using its data to display: "This product uses FHFA data but is neither endorsed
nor certified by FHFA." Preserve source attribution even when that service
notice is not applicable. This record is an engineering summary, not legal
advice.

## Admission checks and limits

- Require exactly 51 unique state/DC rows and reject territories or totals.
- Reject duplicate report URLs, duplicate state rows, unknown publication
  dates, unsupported layouts, missing headings, nonnumeric cells, or absent
  warning text.
- Require each extracted report URL to have exactly one layout-check record.
- Treat short-term HPI variants as noninterchangeable; do not substitute
  all-transactions, expanded-data, distress-free, or non-seasonally adjusted
  values.
- Record that the index is nominal and does not cover nonconforming mortgages,
  government-insured loans, condominiums, cooperatives, or multi-unit property.
- Stop admission when a report cannot be extracted and manually verified
  unambiguously.
