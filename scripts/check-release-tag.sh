#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/release.env"

expected="v${PKG_VERSION}"
[ -z "${PKG_RELEASE:-}" ] || expected="${expected}-r${PKG_RELEASE}"
actual="${1:-${GITHUB_REF_NAME:-}}"

[ "$actual" = "$expected" ] || {
  printf 'Release tag %s does not match package version %s\n' \
    "${actual:-missing}" "$expected" >&2
  exit 1
}

printf 'release tag OK: %s\n' "$actual"
