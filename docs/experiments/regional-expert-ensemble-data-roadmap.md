# Regional expert ensemble data roadmap

Checked August 30, 2026.

The key distinction is this: the verified ensemble used synthetic data shaped like official economic datasets. We have not yet produced a real-world forecast result using actual publisher values.

## Data used in the verified experiment

The synthetic bundle covered all 50 states and Washington, DC from 2015 Q1 through 2025 Q4. It reproduced revisions and publication delays so we could test the point-in-time controls.

The synthetic records represented:

| Expert | Data fields |
|---|---|
| Labor | QCEW third-month employment growth, including a prior lag |
| Business | QCEW establishment and total-wage growth |
| Growth | BEA real GDP and personal-income growth |
| Housing | FHFA quarterly and annual house-price changes |

QCEW observations included preliminary and final vintages with different publication dates. That allowed the system to prove that it selects information available at the forecast date and reserves final employment values for later scoring.

This synthetic use is explicit in the [fixture](../../test/support/regional_fixture.ex#L12) and the [dated experiment report](regional-expert-ensemble.md#L56). The successful Elixir-Python comparison proves that the two implementations follow the same contract. It does not prove forecast quality.

## Real data the system is designed to use

The production contract admits three first-party sources:

1. BLS QCEW

   - Monthly employment within each quarter
   - Establishment counts
   - Total wages
   - Historical preliminary and revised releases
   - Final third-month employment for outcome scoring

2. BEA Regional Economic Accounts

   - State real GDP from `SQGDP9`
   - State personal income from `SQINC1`
   - Archived releases, not the mutable current history

   BEA confirms that its archive contains the estimates published with previous releases, including estimates that have since been superseded. [BEA Regional Accounts archive](https://apps.bea.gov/histdata/RegionalAccounts.html)

3. FHFA House Price Index

   - Seasonally adjusted purchase-only state HPI
   - Published quarterly and annual price changes
   - Extracted from the archived report available at each forecast date

   FHFA explains that it revises historical indexes as additional mortgage transactions arrive. That makes archived reports necessary for an honest historical test. [FHFA HPI FAQ](https://www.fhfa.gov/faqs/hpi)

These requirements and features are defined in the [shared model contract](../../contracts/regional-expert-ensemble.v1.json#L19).

## What we should use next

The first priority is not another dataset. It is assembling and admitting the real QCEW, BEA, and FHFA historical bundle, then running the dated 2020 Q1 through 2025 Q3 backtest. Until that happens, every new expert would still be resting on an untested real-data foundation.

After that, I recommend this order:

| Finding | Status | Source | Date | Limit |
|---|---|---|---|---|
| Expand QCEW into state industry features such as sector employment growth, industry shares, concentration, and shift-share momentum. | Add first | [BLS QCEW](https://www.bls.gov/cew/home.htm), [revision history](https://www.bls.gov/cew/revisions/home.htm) | Checked August 30, 2026 | Detailed cells can be suppressed. QCEW cautions that its data were not originally designed as a continuous time series. |
| Add state business applications as an early signal of new employer activity. | Add second | [Census Business Formation Statistics](https://www.census.gov/econ/bfs/data.html), [historical releases](https://www.census.gov/econ/bfs/data/historic.html) | Checked August 30, 2026 | Formation estimates can be projected and revised. Some historical release gaps must be represented explicitly. |
| Add building permits as a leading construction and housing indicator. | Add third | [Census Building Permits Survey](https://www.census.gov/construction/bps/index.html), [release schedule](https://www.census.gov/construction/bps/schedule.html) | Checked August 30, 2026 | Preliminary values are revised, so archived release files are required. |
| Add electricity sales, prices, and generation by state and sector. | Add fourth | [EIA API](https://www.eia.gov/opendata/documentation.php) | API version current March 2026 | Most useful in energy, manufacturing, and weather-sensitive states. The API requires a key, pagination, and prospective vintage capture. |
| Add hires, separations, job creation, and job destruction. | Investigate | [Census Quarterly Workforce Indicators](https://www.census.gov/data/developers/data-sets/qwi.html) | Page revised May 20, 2026 | Excellent labor-flow coverage, but we must first prove that historical publication vintages can be reconstructed. |
| Add bank loan, deposit, delinquency, and capital measures. | Later expert | [FDIC data downloads](https://www.fdic.gov/bank-data-guide/data-downloads), [FDIC API](https://api.fdic.gov/banks/docs/) | Guide updated February 18, 2026 | Bank mergers and changing identifiers complicate history. Headquarters and branch locations do not necessarily represent borrower location. |
| Add Treasury yield-curve measures as national context. | Gate context only | [Daily Treasury rates](https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?page=0&type=daily_treasury_yield_curve) | Checked August 30, 2026 | Rates repeat across every state, so they should interact with local housing, industry, and credit exposure rather than become a standalone state expert. |
| Add annual industry and employer-size structure. | Structural context | [Census County Business Patterns](https://www.census.gov/programs-surveys/cbp.html) | Page revised August 5, 2026 | Annual data arrive slowly and may duplicate information available earlier through QCEW. |

## Recommended future expert set

The expanded system would look like this:

- Labor momentum: aggregate QCEW
- Industry momentum: detailed QCEW sectors
- Business formation: Census BFS
- Construction pipeline: Census building permits
- Economic growth: BEA GDP and income
- Housing: FHFA HPI
- Energy: EIA electricity activity
- Labor flows: Census QWI, if vintage reconstruction succeeds
- Credit: FDIC bank health
- National conditions: Treasury rates supplied to the gate

The best immediate experiment is the QCEW industry expert. It uses the source machinery we already have, adds meaningful state differences, and avoids introducing a new publisher before the real baseline is verified. After that, Business Formation Statistics and building permits offer the strongest genuinely new leading signals.
