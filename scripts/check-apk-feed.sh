#!/bin/sh

# Guard the shared-feed membership contract:
# https://github.com/Nikitid/openwrt-feed/blob/main/docs/MEMBER_INTEGRATION.md

set -eu

fail() {
  printf 'check-apk-feed: %s\n' "$*" >&2
  exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/apk-feed.env"

public_key="$root/$OPENWRT_APK_KEY_FILE"
release_workflow="$root/.github/workflows/release.yml"
[ -r "$public_key" ] || fail "public key not found: $OPENWRT_APK_KEY_FILE"

actual="$(sha256sum "$public_key" | awk '{ print $1 }')"
[ "$actual" = "$OPENWRT_APK_TRUST_SHA256" ] \
  || fail "public key checksum mismatch: $actual"
openssl pkey -pubin -in "$public_key" -noout >/dev/null 2>&1 \
  || fail 'release public key is not a valid PEM public key'

# One publisher key for every member application. A second tracked key would
# only add another trust anchor to every router without adding isolation.
for stray in "$root"/keys/*.pem; do
  [ -e "$stray" ] || continue
  [ "$stray" = "$public_key" ] || fail \
    "unexpected key file: ${stray#"$root"/}; the shared feed uses one publisher key"
done

# Match the marker anywhere in the file name, not only at its start: an anchored
# pattern accepts names such as release-private.pem, which is exactly the form a
# signing key is usually given. Names are only a hint, so the contents of every
# tracked key-shaped file are checked as well.
git -C "$root" ls-files --cached --others --exclude-standard \
  | grep -Ei '(^|/)[^/]*(private|signing|secret)[^/]*\.(pem|key|der)$' \
  && fail 'private signing material is tracked'

key_list="$(mktemp)"
trap 'rm -f "$key_list"' EXIT HUP INT TERM
git -C "$root" ls-files --cached --others --exclude-standard \
  | grep -Ei '\.(pem|key|der|p8|p12|pfx)$' >"$key_list" || :
while IFS= read -r candidate; do
  [ -f "$root/$candidate" ] || continue
  if grep -qE 'BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY' "$root/$candidate"; then
    fail "tracked file contains private key material: $candidate"
  fi
done <"$key_list"

# This repository builds and signs only its own package. The signed index is
# assembled by Nikitid/openwrt-feed from published releases, so nothing here may
# grow its own feed assembly or bootstrap installer again.
grep -Fq './scripts/build-apk.sh' "$release_workflow" \
  || fail 'release workflow does not build the signed APK'
grep -Fq 'dist/apk/*' "$release_workflow" \
  || fail 'release workflow does not publish the signed APK asset'
grep -Fq 'event_type=member-release' "$release_workflow" \
  || fail 'release workflow does not notify the shared feed'
grep -Fq 'continue-on-error: true' "$release_workflow" \
  || fail 'the shared-feed notification must not fail a release'
# shellcheck disable=SC2016 # the workflow literal is matched, not expanded
grep -Fq 'repos/${OPENWRT_FEED_REPOSITORY}/dispatches' "$release_workflow" \
  || fail 'release workflow dispatches to an unexpected repository'
grep -Fq 'packages.adb' "$release_workflow" \
  && fail "index assembly belongs to $OPENWRT_FEED_REPOSITORY, not here"

for gone in build-apk-feed.sh install-openwrt25.sh test-apk-bootstrap.sh; do
  [ ! -e "$root/scripts/$gone" ] \
    || fail "the shared installer replaced scripts/$gone; remove it"
done

# Routers bootstrap through the shared installer only.
for document in README.md README.en.md; do
  grep -Fq "$OPENWRT_FEED_INSTALLER" "$root/$document" \
    || fail "$document does not point at the shared installer"
done

# Every documented package transaction names the package it touches.
for document in README.md README.en.md AGENTS.md SECURITY.md CHANGELOG.md \
    docs/ARCHITECTURE.md docs/OPERATIONS.md; do
  [ -f "$root/$document" ] || continue
  grep -nE '(apk|opkg)[[:space:]]+upgrade[[:space:]]*$' "$root/$document" \
    && fail "$document documents a blanket package upgrade"
done

printf 'check-apk-feed OK\n'
