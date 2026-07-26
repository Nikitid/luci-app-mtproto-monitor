#!/bin/sh

# Extract the postinst and prerm bodies that each packaging path embeds, so
# other checks can inspect exactly what is installed onto a router.
#
# The package is built two ways: the OpenWrt SDK reads the Makefile, the
# SDK-less IPK builder reads scripts/stage-package.sh. Both carry their own copy
# of the maintainer scripts, so both are extracted here and compared elsewhere.
#
# Make collapses '$$' to '$' before the recipe reaches the package, so the
# Makefile copy is normalised the same way and the two copies stay comparable.

set -eu

[ "$#" -eq 1 ] || {
  printf 'Usage: %s OUTPUT_DIR\n' "$0" >&2
  exit 2
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
output="$1"

rm -rf "$output"
mkdir -p "$output"

for name in postinst prerm; do
  awk -v want="$name" '
    $0 ~ ("^define Package/[^/]+/" want "$") { capture = 1; next }
    capture && $0 == "endef" { capture = 0; next }
    capture { gsub(/\$\$/, "$"); print }
  ' "$root/Makefile" >"$output/makefile-$name"
  [ -s "$output/makefile-$name" ] || {
    printf 'extract-maintainer-scripts: Makefile has no %s recipe\n' "$name" >&2
    exit 1
  }

  awk -v marker="cat >\"\$stage/CONTROL/$name\" <<'EOF'" '
    index($0, marker) == 1 { capture = 1; next }
    capture && $0 == "EOF" { capture = 0; next }
    capture { print }
  ' "$root/scripts/stage-package.sh" >"$output/stage-$name"
  [ -s "$output/stage-$name" ] || {
    printf 'extract-maintainer-scripts: stage-package.sh has no %s heredoc\n' \
      "$name" >&2
    exit 1
  }
done

printf '%s\n' "$output"
