# Mint dependency repair

The existing PR 16 CI dependency gate reported Mint 1.9.3 advisories CVE-2026-82728 and CVE-2026-82729. The [publisher patch release](https://github.com/elixir-mint/mint/releases/tag/v1.10.0) fixes these in 1.10.0. The current Finch requirement permits that version.

The lock change was prepared using the Hex 1.10.0 package metadata, verified tarball SHA-256 and internal package checksum. Declared package requirements are unchanged from 1.9.3. `mix deps.get --check-locked`, `mix hex.audit`, formatting, tests and synthetic EDA must pass in both existing digest-pinned CI images before acceptance. No advisory is ignored and no runtime version is upgraded by this repair.
