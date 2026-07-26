#!/bin/sh

# The Makefile (SDK/APK path) and scripts/stage-package.sh (SDK-less IPK path)
# each carry their own copy of the postinst and prerm bodies. Nothing forces
# them to agree, so an edit to one alone would make the APK and the IPK behave
# differently on a router while every other check still passes.

set -eu

fail() {
  printf 'check-packaging-parity: %s\n' "$*" >&2
  exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

"$root/scripts/extract-maintainer-scripts.sh" "$work/maintainer" >/dev/null

for name in postinst prerm; do
  cmp -s "$work/maintainer/makefile-$name" "$work/maintainer/stage-$name" || {
    diff -u "$work/maintainer/makefile-$name" "$work/maintainer/stage-$name" >&2 \
      || true
    fail "Makefile and stage-package.sh disagree on $name"
  }
done

# Both paths must install the same files at the same paths.
sed -n 's/^[[:space:]]*\$(INSTALL_[A-Z]*)[[:space:]]*\.\/\([^[:space:]]*\)[[:space:]]*\$(1)\([^[:space:]]*\).*/\1 \2/p' \
  "$root/Makefile" | sort >"$work/makefile-files"
sed -n 's/^install_file[[:space:]]*[0-7]\{3\}[[:space:]]*\([^[:space:]]*\)[[:space:]]*\([^[:space:]]*\).*/\1 \2/p' \
  "$root/scripts/stage-package.sh" | sort >"$work/stage-files"

cmp -s "$work/makefile-files" "$work/stage-files" || {
  diff -u "$work/makefile-files" "$work/stage-files" >&2 || true
  fail 'Makefile and stage-package.sh install different files'
}

[ -s "$work/stage-files" ] || fail 'no installed files were detected'

# The catalogues are generated rather than copied, so the file-list comparison
# above cannot see them. Both paths must still compile them with the same tool
# into the same directory, or one package would ship untranslated.
for packaging in Makefile scripts/stage-package.sh; do
  grep -Fq 'scripts/po2lmo.py' "$root/$packaging" \
    || fail "$packaging does not compile the translation catalogues"
  grep -Fq '/usr/lib/lua/luci/i18n' "$root/$packaging" \
    || fail "$packaging does not install the catalogues where LuCI looks"
done

printf 'check-packaging-parity OK: %s files\n' "$(wc -l <"$work/stage-files" | tr -d ' ')"
