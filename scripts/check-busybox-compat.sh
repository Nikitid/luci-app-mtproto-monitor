#!/bin/sh

# Router-side scripts run against BusyBox applets, not GNU coreutils. Developer
# machines and CI runners provide the GNU versions, so a GNU-only option is
# accepted locally and every test passes while the router silently does
# something else.
#
# Every pattern below was verified against BusyBox v1.37.0 as shipped by the
# supported target (OpenWrt 25.12.5, mediatek/filogic):
#
#   sort   Usage: sort [-nru] [FILE]...            -- no -o
#   grep   Usage: grep [-HhnlLoqvsrRiwFE] ...      -- no -P
#   find   no -printf action
#   base64 applet not present; openssl provides it
#
# Only patterns verified that way belong here.

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$root"

status=0

report() {
  printf 'busybox-compat: %s\n' "$1" >&2
  status=1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

# Everything that is installed onto a router: the collector, its init script and
# the maintainer scripts both packaging paths embed.
"$root/scripts/extract-maintainer-scripts.sh" "$work/maintainer" >/dev/null
{
  find runtime -type f
  find "$work/maintainer" -type f
} | sort >"$work/shipped"

check_pattern() {
  pattern="$1"
  message="$2"
  exclude="${3:-}"
  while IFS= read -r file; do
    grep -nE "$pattern" "$file" | while IFS= read -r hit; do
      [ -n "$exclude" ] \
        && printf '%s' "$hit" | grep -qE "$exclude" && continue
      printf '%s:%s\n' "${file#"$work/"}" "$hit"
    done
  done <"$work/shipped" >"$work/hits"
  [ -s "$work/hits" ] || return 0
  while IFS= read -r hit; do
    report "$message: $hit"
  done <"$work/hits"
}

# BusyBox sort ignores -o, leaves the target file untouched and writes the
# sorted result to stdout instead.
check_pattern '(^|[;&|[:space:]])sort([[:space:]]+-[A-Za-z]+)*[^|;&]*[[:space:]]-o([[:space:]]|$)' \
  'BusyBox sort does not support -o; write to a temporary file and mv it'

# BusyBox grep has no PCRE support.
check_pattern '(^|[;&|[:space:]])grep([[:space:]]+-[A-Za-z]*P)' \
  'BusyBox grep does not support -P'

# BusyBox find has no -printf.
check_pattern '(^|[;&|[:space:]])find[^|;&]*[[:space:]]-printf([[:space:]]|$)' \
  'BusyBox find does not support -printf'

# The base64 applet is not present in the supported build; openssl provides it.
check_pattern '(^|[;&|[:space:]])base64([[:space:]]|$)' \
  'the base64 applet is unavailable on OpenWrt; use openssl base64' \
  'openssl[[:space:]]+base64'

if [ "$status" = 0 ]; then
  printf 'busybox-compat OK\n'
fi

exit "$status"
