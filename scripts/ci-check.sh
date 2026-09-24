#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$root"

./scripts/check-version-sync.sh
./scripts/check-readme.sh
./scripts/check-public-tree.sh
./scripts/check-apk-feed.sh
./scripts/check-packaging-parity.sh
./scripts/check-busybox-compat.sh
find runtime scripts -type f -name '*.sh' -exec sh -n {} +
find luci -type f -name '*.js' -exec node --check {} +
PYTHONPYCACHEPREFIX="$root/build/pycache" \
  python3 -m py_compile scripts/pack-ipk.py scripts/po2lmo.py scripts/test-po2lmo.py
PYTHONPYCACHEPREFIX="$root/build/pycache" \
  python3 ./scripts/test-po2lmo.py
python3 - <<'PY'
import json
from pathlib import Path

for path in Path("luci").glob("*.json"):
    json.loads(path.read_text())
    print(f"json OK: {path}")
PY
./scripts/test-runtime.sh
./scripts/test-firewall.sh
./scripts/build-ipk.sh
first="$(sha256sum dist/*.ipk | awk '{print $1}')"
./scripts/build-ipk.sh
second="$(sha256sum dist/*.ipk | awk '{print $1}')"
[ "$first" = "$second" ] || {
  printf 'non-deterministic IPK build: %s != %s\n' "$first" "$second" >&2
  exit 1
}
git diff --check
printf 'ci-check OK\n'
