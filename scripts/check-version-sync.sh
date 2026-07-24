#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/release.env"

field() {
  sed -n "s/^$1:=//p" "$root/Makefile" | head -n 1
}

[ "$(field PKG_NAME)" = "$PKG_NAME" ]
[ "$(field PKG_VERSION)" = "$PKG_VERSION" ]
[ "$(field PKG_RELEASE)" = "$PKG_RELEASE" ]
[ "$(field PKGARCH)" = "$PKG_ARCH" ]
printf 'check-version-sync OK: %s %s %s\n' "$PKG_NAME" "$PKG_VERSION" "$PKG_ARCH"
