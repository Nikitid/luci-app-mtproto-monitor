#!/bin/sh

set -eu

fail() {
  printf 'build-apk-feed: %s\n' "$*" >&2
  exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/release.env"
. "$root/apk-feed.env"

sdk="${OPENWRT_SDK_DIR:-}"
signing_key="${OPENWRT_APK_SIGNING_KEY:-}"
release_tag="${OPENWRT_APK_RELEASE_TAG:-}"
public_key="$root/$OPENWRT_APK_KEY_FILE"
output="$root/dist/apk-feed"

[ -d "$sdk" ] || fail 'OPENWRT_SDK_DIR is required'
[ -r "$signing_key" ] || fail 'OPENWRT_APK_SIGNING_KEY is required'
[ -r "$public_key" ] || fail 'release public key is missing'
[ "$(basename "$sdk")" = "${OPENWRT_APK_SDK_ARCHIVE%.tar.zst}" ] \
  || fail 'unexpected SDK directory'
[ "$(sha256sum "$public_key" | awk '{ print $1 }')" = \
  "$OPENWRT_APK_TRUST_SHA256" ] || fail 'public key checksum mismatch'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
openssl ec -in "$signing_key" -pubout -out "$tmp/public.pem" >/dev/null 2>&1 \
  || fail 'invalid signing key'
cmp -s "$tmp/public.pem" "$public_key" \
  || fail 'signing key does not match the tracked public key'

OPENWRT_APK_SIGNING_KEY="$signing_key" \
  OPENWRT_APK_PUBLIC_KEY="$public_key" \
  "$root/scripts/build-apk.sh"

apk_tool="$sdk/staging_dir/host/bin/apk"
[ -x "$apk_tool" ] || fail 'SDK apk tool was not found'
package_name="${PKG_NAME}-${PKG_VERSION}.apk"
package_path="$root/dist/$package_name"
[ -r "$package_path" ] || fail 'built APK was not found'

rm -rf "$output"
mkdir -p "$output"
cp "$package_path" "$output/$package_name"
"$apk_tool" --allow-untrusted adbsign \
  --sign-key "$signing_key" "$output/$package_name"
"$apk_tool" --keys-dir "$root/keys" verify "$output/$package_name"
(
  cd "$output"
  "$apk_tool" mkndx \
    --keys-dir "$root/keys" \
    --sign-key "$signing_key" \
    --description 'MTProto Monitor for OpenWrt 25.12' \
    --output packages.adb \
    "$package_name"
)
"$apk_tool" --keys-dir "$root/keys" verify "$output/packages.adb"

cp "$public_key" "$output/mtproto-monitor-release.pem"
release_base="$OPENWRT_APK_RELEASE_BASE"
[ -z "$release_tag" ] \
  || release_base="https://github.com/Nikitid/mtproto-monitor/releases/download/$release_tag"
sed "s|^OPENWRT_APK_RELEASE_BASE=https://.*|OPENWRT_APK_RELEASE_BASE=$release_base|" \
  "$root/scripts/install-openwrt25.sh" >"$output/install-openwrt25.sh"
chmod 0755 "$output/install-openwrt25.sh"
(
  cd "$output"
  sha256sum "$package_name" packages.adb mtproto-monitor-release.pem \
    install-openwrt25.sh >SHA256SUMS.apk
  sha256sum -c SHA256SUMS.apk
)

printf 'APK feed built in %s\n' "$output"
