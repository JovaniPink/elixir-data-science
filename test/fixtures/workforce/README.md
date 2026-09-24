# Synthetic workforce fixture

`synthetic.csv` is synthetic test data for `scripts/run_workforce_eda.exs`. It
contains no real employment data: no value was retrieved from BLS, QCEW, or any
other publisher, and no value describes an actual state, person, or employer.

## Provenance

- Source: authored in this repository by its maintainer; there is no external
  source.
- Created: September 8, 2026, in commit `852199e`. No retrieval took place.
- License: repository [MIT License](../../../LICENSE), like other
  repository-authored material.
- Permitted use: automated tests and CI contract checks for the workforce EDA
  script. It must not be cited as, or combined with, observed employment data.

## Generation rule

The header is `region,employment,unit`. Rows follow the 51 two-digit state and
District of Columbia FIPS codes in ascending order (`01` through `56`, skipping
the unassigned codes `03`, `07`, `14`, `43`, and `52`). For the row at 1-based
position `i`, `employment` is `100 * i * i` and `unit` is `jobs`. The file uses
LF line endings with a trailing newline. The FIPS codes only give the rows the
canonical shape; the values are arbitrary.

| Column | Type | Meaning |
|---|---|---|
| `region` | two-digit string | State or District of Columbia FIPS code used as a row key |
| `employment` | nonnegative integer | Synthetic weight, `100 * i * i` |
| `unit` | string | Always `jobs`, the unit the script requires |

## Release reference

`release.json` marks the input as synthetic and pins its SHA-256 in
`input_sha256`. The script rejects any input whose bytes do not match that
hash. `test/elixir_data_science/workforce_eda_script_test.exs` regenerates the
file from the rule above and checks that hash, so any edit to the fixture must
update `release.json` in the same change.
