#!/bin/sh

set -eu

fail() {
  printf 'check-apk-feed: %s\n' "$*" >&2
  exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/apk-feed.env"

public_key="$root/$OPENWRT_APK_KEY_FILE"
[ -r "$public_key" ] || fail "public key not found: $OPENWRT_APK_KEY_FILE"
[ "$(sha256sum "$public_key" | awk '{ print $1 }')" = \
  "$OPENWRT_APK_TRUST_SHA256" ] || fail 'public key checksum mismatch'
openssl pkey -pubin -in "$public_key" -noout >/dev/null 2>&1 \
  || fail 'release public key is invalid'

git -C "$root" ls-files --cached --others --exclude-standard \
  | grep -Ei '(^|/)(private|signing)[^/]*\.(pem|key)$' \
  && fail 'private signing material is tracked'

grep -Fq "OPENWRT_APK_TRUST_SHA256=$OPENWRT_APK_TRUST_SHA256" \
  "$root/scripts/install-openwrt25.sh" \
  || fail 'installer key checksum is out of sync'
grep -Fq "OPENWRT_APK_CHANNEL_BASE=$OPENWRT_APK_CHANNEL_BASE" \
  "$root/scripts/install-openwrt25.sh" \
  || fail 'installer feed URL is out of sync'

printf 'check-apk-feed OK\n'
