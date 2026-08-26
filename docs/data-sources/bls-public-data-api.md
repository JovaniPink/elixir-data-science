# BLS Public Data API source record

_Source record first verified August 16, 2026; BLS terms and release coverage
rechecked August 26, 2026._

## Decision

The first experiment retrieves two first-party U.S. Bureau of Labor Statistics
(BLS) series directly from the BLS Public Data API at runtime:

| Series ID | Observed measure | Treatment in this experiment |
|---|---|---|
| `CUUR0000SA0` | CPI-U, U.S. city average, all items, not seasonally adjusted, monthly | Convert the index to its 12-month percentage change |
| `LNS14000000` | Civilian unemployment rate, seasonally adjusted, monthly | Use the published rate as a descriptive feature |

The fixed API request boundary is the inclusive year range 2006-2026. The API
returns only released values within that boundary; in the August 26, 2026 run,
both selected series were available through July 2026. The first 12 months are
used only to calculate the CPI lag. October 2025 is unavailable for both
selected series, leaving 234 aligned monthly observations from January 2007
through July 2026. Data is retrieved when the script or notebook runs; raw BLS
data is not committed to this repository.

## Access and permitted use

- API endpoint: <https://api.bls.gov/publicAPI/v2/timeseries/data/>
- Developer documentation: <https://www.bls.gov/developers/>
- API signatures: <https://www.bls.gov/developers/api_signature_v2.htm>
- Current terms: <https://www.bls.gov/developers/termsOfService.htm>
- CPI series-code explanation: <https://www.bls.gov/cpi/factsheets/cpi-series-ids.htm>
- July 2026 CPI release: <https://www.bls.gov/news.release/archives/cpi_08122026.htm>
- July 2026 Employment Situation: <https://www.bls.gov/news.release/archives/empsit_08072026.htm>
- October 2025 CPI notice: <https://www.bls.gov/cpi/additional-resources/2025-federal-government-shutdown-impact-cpi-faq.htm>
- October 2025 CPS notice: <https://www.bls.gov/cps/methods/2025-federal-government-shutdown-impact-cps.htm>

The BLS terms rechecked on August 26, 2026 state that data accessed through
BLS.gov should not include controls on end use. They also require API users to
cite the retrieval date and clearly state:

> BLS.gov cannot vouch for the data or analyses derived from these data after
> the data have been retrieved from BLS.gov.

The terms prohibit falsely representing modified content as BLS content and
allow BLS to impose or enforce access limits. The implementation therefore:

- records a UTC retrieval timestamp;
- preserves the original series IDs and source endpoint;
- retains unavailable monthly records and their BLS footnotes rather than
  silently imputing them;
- makes anonymous requests in at most 10-year inclusive windows;
- does not bypass request limits or require a registration key;
- labels all transformations and model outputs as repository-derived; and
- does not use the BLS logo.

This is an engineering record of the reviewed source terms, not legal advice.
The terms can change and must be rechecked before a materially different use.

## Measurement and analysis boundaries

- CPI-U measures average price change for an urban consumer population. BLS
  says that population covers over 90 percent of the U.S. population but
  excludes rural nonmetropolitan residents, farm households, military
  installations, religious communities, and institutions.
- CPI-U is not a complete cost-of-living measure and need not match any
  household's individual inflation experience.
- The CPI series is not seasonally adjusted; the unemployment series is. A
  12-month CPI change reduces recurring seasonality but does not make the two
  source series methodologically identical.
- BLS series may be revised. This repository records retrieval time, but a
  rerun can legitimately produce different values.
- BLS marks October 2025 unavailable in both selected series. Its official CPI
  and Current Population Survey notices attribute the missing source data to
  the 2025 lapse in appropriations. This experiment drops that month and does
  not impute it.
- The July CPI and Employment Situation releases establish that July 2026 was
  released before the August 26 run. The run found no later common month in the
  selected API series and does not manufacture August values.
- The August 26 API responses marked no selected source values preliminary, so
  no derived observation was flagged preliminary. That point-in-time result
  does not prevent later source revisions.
- K-means is fit to standardized inflation and unemployment. It is sensitive
  to the selected years, feature definitions, number of clusters, and random
  initialization. A fixed seed and repeated starts improve reproducibility but
  do not turn clusters into objective economic regimes.
- Monthly observations overlap in their 12-month CPI windows and are serially
  correlated. The experiment does not treat them as independent evidence.
- Cluster IDs are arbitrary. The output is an ex-post description of the
  selected sample, not causal inference, a recession classifier, a forecast,
  a trading signal, or financial advice.

## Why FRED is not the model-training source

FRED is useful for discovery and economic-data reference, but its
[legal terms](https://fred.stlouisfed.org/legal/terms/) reviewed on August 16,
2026 prohibit using FRED services or content in connection with developing or
training machine-learning systems. This experiment therefore does not retrieve
the selected series from FRED and does not train on FRED-delivered data. The
source boundary is first-party BLS API data under the BLS terms recorded above.
