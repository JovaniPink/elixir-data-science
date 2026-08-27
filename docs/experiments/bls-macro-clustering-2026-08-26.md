# BLS macro clustering run record: August 26, 2026

_Executed August 26, 2026 at 19:09:26 UTC._

## Question and claim boundary

Can K-means separate recurring combinations of observed U.S. CPI inflation and
unemployment in a fixed 2006-2026 API request boundary, using the jointly
released observations through July 2026?

This is an ex-post descriptive exercise. The run does not establish causal
economic regimes, select an optimal cluster count, classify recessions,
forecast future data, or produce a trading or financial-advice signal.

## Run manifest

| Item | Value |
|---|---|
| Source | BLS Public Data API |
| Source series | `CUUR0000SA0`, `LNS14000000` |
| Retrieval time | August 26, 2026 at 19:09:26 UTC |
| Requested years | 2006-2026 |
| Anonymous API windows | 2006-2015, 2016-2025, 2026 |
| Latest common source month | July 2026 |
| Derived observation period | January 2007-July 2026 |
| Derived features | 12-month CPI-U change, unemployment-rate level |
| Standardization | Population mean and standard deviation per feature |
| K-means configuration | 3 clusters, K-means++ initialization, seed 42, 20 starts, maximum 300 iterations, tolerance `1.0e-4` |
| Aligned observations | 234 months |
| Unavailable source values | 2, both for October 2025; retained and not imputed |
| Preliminary source values | 0 |
| Preliminary aligned observations | 0 |
| API messages | None |
| Model inertia | 135.2229 in standardized feature space |

The [July CPI release](https://www.bls.gov/news.release/archives/cpi_08122026.htm)
and [July Employment Situation](https://www.bls.gov/news.release/archives/empsit_08072026.htm)
were published on August 12 and August 7, respectively. They establish that
July observations had been released before this run. The selected API series
contained no later common month at retrieval time.

## Unavailable and preliminary values

| Series | Month | API status |
|---|---|---|
| `CUUR0000SA0` | October 2025 | Unavailable due to the 2025 lapse in appropriations |
| `LNS14000000` | October 2025 | Unavailable due to the 2025 lapse in appropriations |

BLS's official [CPI notice](https://www.bls.gov/cpi/additional-resources/2025-federal-government-shutdown-impact-cpi-faq.htm)
and [Current Population Survey notice](https://www.bls.gov/cps/methods/2025-federal-government-shutdown-impact-cps.htm)
attribute the October 2025 gap to the 2025 lapse in appropriations. The code
retained the unavailable records and footnotes, excluded the month from
alignment, and performed no interpolation.

None of the three API responses marked a selected source value preliminary.
Consequently, none of the 234 aligned observations inherited a preliminary
flag from its current CPI value, 12-month CPI lag, or unemployment value. This
is a report of the August 26 response metadata, not a claim that published
series cannot later be revised.

## Observed profile summaries

Cluster numbers are implementation labels, not ordered economic categories.
The period columns report the earliest and latest assigned months; they do not
mean every month in between belongs to that cluster.

| Cluster ID | Months | Mean 12-month CPI inflation | Mean unemployment rate | Earliest assigned month | Latest assigned month |
|---|---:|---:|---:|---|---|
| 0 | 74 | 1.48% | 8.63% | November 2008 | December 2020 |
| 2 | 132 | 2.26% | 4.52% | January 2007 | July 2026 |
| 1 | 28 | 6.64% | 4.31% | June 2008 | April 2023 |

Within this run, one cluster has a higher mean unemployment rate, one has a
higher mean inflation rate, and the largest has lower means on both dimensions
relative to those two groups. That statement describes the fitted profiles in
this sample; it does not claim that the groups are stable, causal, or
predictive.

The profile means hide within-cluster dispersion, time ordering, and changes
in measurement conditions. The 3-cluster choice is illustrative rather than
selected by a pre-specified validation criterion. Inertia would mechanically
fall as more clusters are added, so the reported value alone does not validate
the choice.

The preserved [August 16 Elixir run](bls-macro-clustering.md) and its sibling
[Python run record](https://github.com/JovaniPink/python-data-science/blob/main/docs/experiments/bls-macro-clustering.md)
cover only the 2006-2025 request boundary. They remain historical comparison
evidence and are not presented as replications of this extended sample.

## Reproduction

Run:

```bash
mix run scripts/run_bls_macro_clustering.exs
```

The source data can be revised, so later profile values may differ. Every rerun
must report its own UTC retrieval timestamp, latest common month, unavailable
source records, and preliminary values.

> BLS.gov cannot vouch for the data or analyses derived from these data after
> the data have been retrieved from BLS.gov.
