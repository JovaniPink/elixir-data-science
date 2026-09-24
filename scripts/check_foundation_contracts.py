"""Verify the checked-in public-safe foundation snapshot; no credentials or network."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "contracts/data-foundation"
checksums = json.loads((root / "checksums.json").read_text())
present = {path.name for path in root.iterdir() if path.name != "checksums.json"}
if present != set(checksums):
    unlisted = sorted(present - set(checksums))
    missing = sorted(set(checksums) - present)
    raise SystemExit(f"contract snapshot set mismatch: unlisted={unlisted} missing={missing}")
for name, expected in checksums.items():
    path = root / name
    if path.is_symlink() or path.parent != root or not path.is_file():
        raise SystemExit("invalid contract snapshot path")
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected:
        raise SystemExit(f"contract checksum mismatch: {name}")
    json.loads(raw)
print(f"Verified {len(checksums)} foundation contract snapshots; no source qualification implied.")
