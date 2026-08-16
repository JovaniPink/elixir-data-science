# BLS macro clustering run record

_Executed August 16, 2026 at 19:24:08 UTC._

## Question and claim boundary

Can K-means separate recurring combinations of observed U.S. CPI inflation and
unemployment in a fixed 2006–2025 sample?

This is an ex-post descriptive exercise. The run does not establish causal
economic regimes, select an optimal cluster count, classify recessions,
forecast future data, or produce a trading or financial-advice signal.

## Run manifest

| Item | Value |
|---|---|
| Source | BLS Public Data API |
| Source series | `CUUR0000SA0`, `LNS14000000` |
| Requested years | 2006–2025 |
| Anonymous API windows | 2006–2015, 2016–2025 |
| Derived features | 12-month CPI-U change, unemployment-rate level |
| Standardization | Population mean and standard deviation per feature |
| K-means configuration | 3 clusters, seed 42, 20 starts |
| Aligned observations | 227 months |
| Missing source month | October 2025 in both series; not imputed |
| Model inertia | 129.7056 in standardized feature space |

BLS's official [CPI notice](https://www.bls.gov/cpi/additional-resources/2025-federal-government-shutdown-impact-cpi-faq.htm)
and [Current Population Survey notice](https://www.bls.gov/cps/methods/2025-federal-government-shutdown-impact-cps.htm)
attribute the October 2025 data gap to the 2025 lapse in appropriations. The
code retains the API's unavailable records and footnotes, excludes the month
from alignment, and performs no interpolation.

## Observed profile summaries

Cluster numbers are implementation labels, not ordered economic categories.

| Cluster ID | Months | Mean 12-month CPI inflation | Mean unemployment rate |
|---|---:|---:|---:|
| 2 | 74 | 1.48% | 8.63% |
| 1 | 125 | 2.20% | 4.54% |
| 0 | 28 | 6.64% | 4.31% |

Within this run, one cluster has a higher mean unemployment rate, one has a
higher mean inflation rate, and the largest has lower means on both dimensions
relative to those two groups. That statement is a description of cluster
profiles, not a claim that the groups are stable, causal, or predictive.

The profile means hide within-cluster dispersion, time ordering, and changes
in measurement conditions. The 3-cluster choice is illustrative rather than
selected by a pre-specified validation criterion. Inertia would mechanically
fall as more clusters are added, so the reported value alone does not validate
the choice.

## Reproduction

Run:

```bash
mix run scripts/run_bls_macro_clustering.exs
```

The source data can be revised, so later profile values may differ. Every rerun
must report its own UTC retrieval timestamp and unavailable source records.

> BLS.gov cannot vouch for the data or analyses derived from these data after
> the data have been retrieved from BLS.gov.
