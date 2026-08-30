# BEA Regional Accounts archives source record

_Source, archive, methodology, and rights pages checked August 30, 2026._

## Decision

The regional expert ensemble is designed to admit archived U.S. Bureau of
Economic Analysis quarterly state estimates from `SQGDP9`, Real GDP by State,
and `SQINC1`, Personal Income Summary. The population is the 50 states and
Washington, DC. Territories are excluded.

This record approves the BEA Regional Accounts archive as the point-in-time
authority. It does not claim that all required archived releases have been
downloaded, normalized, or admitted.

## Publisher evidence

- Publisher: U.S. Bureau of Economic Analysis
- GDP by state: <https://www.bea.gov/data/gdp/gdp-state>
- Previously published estimates: <https://apps.bea.gov/histdata/RegionalAccounts.html>
- API user guide: <https://apps.bea.gov/api/_pdf/bea_web_service_api_user_guide.pdf>
- GDP by state methodology: <https://www.bea.gov/resources/methodologies/gdp-by-state>
- State personal-income methodology: <https://www.bea.gov/sites/default/files/methodologies/SPI-Methodology.pdf>
- Copyright FAQ: <https://www.bea.gov/help/faq/147>
- Data dissemination practices: <https://www.bea.gov/about/policies-and-information/data-dissemination>

BEA identifies `SQGDP9` as real GDP by state and `SQINC1` as the quarterly
personal-income summary. State summary tables are denominated in millions of
dollars. Quarterly state levels are published at seasonally adjusted annual
rates. Real GDP is inflation-adjusted and chain-weighted; personal income is in
current dollars.

The archive contains Regional Accounts values published with earlier news
releases. BEA labels those estimates as superseded and provides them for
research. That is the required property for this historical backtest. Current
interactive tables or API results must not be substituted for an archived
release at an earlier forecast origin.

## Point-in-time policy

For each archived release:

1. Bind the release to an official BEA release date and archived file URL.
2. Select the all-industry real GDP level from `SQGDP9` and total personal
   income from `SQINC1` for every state and DC.
3. Preserve the reference quarter, release date, archive identifier, units,
   seasonal adjustment, and annual-rate status supplied with that release.
4. At a forecast origin, select the newest archived publication whose release
   date is on or before the calendar quarter-end.

The current BEA API is useful for metadata and current estimates, but current
history is not point-in-time evidence. API access also requires registration
and agreement to BEA's terms. The archive remains authoritative for historical
folds.

## Normalized observations

Each admitted row in `observations.bea` contains:

| Field | Meaning |
|---|---|
| `state_fips` | Two-character state or DC FIPS from the shared contract |
| `observation_quarter` | Canonical `YYYYQn` reference quarter |
| `release_date` | Official date the archived estimates became public |
| `vintage` | Stable identifier tied to the BEA archived release |
| `real_gdp` | Positive `SQGDP9` all-industry state level |
| `personal_income` | Positive `SQINC1` total personal-income state level |

The bundle must retain the publisher's units even though constant rescaling
does not change the natural-log growth rates. Never mix units or reference-year
definitions within a vintage. The model derives year-over-year and
quarter-over-quarter growth only after selecting the release available at the
origin.

## Rights and attribution

BEA states that, unless otherwise noted, information on its website is public
domain and may be reproduced without specific permission. BEA appreciates a
source citation. Preserve the exact publisher URL and retrieval date, label the
normalized panel and forecasts as repository-derived, and do not imply BEA
endorsement. This record is an engineering summary, not legal advice.

## Admission checks and limits

- Record a receipt for every source file used to construct an archived release.
- Require exactly 51 unique state/DC rows for each admitted release.
- Reject missing table identifiers, mixed releases, missing units, unknown
  release dates, duplicate vintage keys, territories, nonpositive levels, and
  files released after the research cutoff.
- Record comprehensive or annual updates that change historical definitions or
  reference years; do not splice current data into an older archive.
- Real GDP chain-weighted components are not additive. This experiment uses the
  published all-industry total and does not sum industries.
- Stop admission if an official release date cannot be bound to the exact
  archived `SQGDP9` and `SQINC1` values.
