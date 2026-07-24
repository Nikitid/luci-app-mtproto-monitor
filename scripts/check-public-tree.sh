#!/bin/sh

set -eu

tracked="$(git ls-files --cached --others --exclude-standard)"

for prefix in build/ dist/ backups/; do
  printf '%s\n' "$tracked" | grep -q "^$prefix" && {
    printf 'generated or private path is tracked: %s\n' "$prefix" >&2
    exit 1
  }
done

for suffix in .key .p12 .pfx .mobileconfig .har; do
  printf '%s\n' "$tracked" | grep -q "${suffix}\$" && {
    printf 'secret-bearing file type is tracked: %s\n' "$suffix" >&2
    exit 1
  }
done

findings="$(mktemp)"
trap 'rm -f "$findings"' EXIT HUP INT TERM
printf '%s\n' "$tracked" | while IFS= read -r file; do
  [ -f "$file" ] || continue
  grep -IHnE \
    'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}' \
    "$file" >>"$findings" 2>/dev/null || true
done
[ ! -s "$findings" ] || {
  cat "$findings" >&2
  exit 1
}
printf 'check-public-tree OK\n'
