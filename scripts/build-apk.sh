#!/bin/sh

# Build and sign this repository's own package with the pinned OpenWrt SDK.
#
# Only this package is produced here. The shared signed index is assembled by
# Nikitid/openwrt-feed from published release assets, so a release never depends
# on a sibling application being ready.

set -eu

fail() {
  printf 'build-apk: %s\n' "$*" >&2
  exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/release.env"
. "$root/apk-feed.env"

sdk="${OPENWRT_SDK_DIR:-}"
signing_key="${OPENWRT_APK_SIGNING_KEY:-}"
public_key="$root/$OPENWRT_APK_KEY_FILE"

[ -n "$sdk" ] || fail 'OPENWRT_SDK_DIR is required'
[ -d "$sdk" ] || fail "SDK directory not found: $sdk"
[ -n "$signing_key" ] || fail 'OPENWRT_APK_SIGNING_KEY is required'
[ -r "$signing_key" ] || fail "signing key not readable: $signing_key"
[ -r "$public_key" ] || fail "public key not found: $OPENWRT_APK_KEY_FILE"

case "$(basename "$sdk")" in
  "${OPENWRT_APK_SDK_ARCHIVE%.tar.zst}") ;;
  *) fail "unexpected SDK directory: $(basename "$sdk")" ;;
esac

for command in make openssl rsync sha256sum; do
  command -v "$command" >/dev/null 2>&1 \
    || fail "required command is missing: $command"
done

actual_key_hash="$(sha256sum "$public_key" | awk '{ print $1 }')"
[ "$actual_key_hash" = "$OPENWRT_APK_TRUST_SHA256" ] \
  || fail "public key checksum mismatch: $actual_key_hash"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

openssl ec -in "$signing_key" -pubout -out "$tmp/derived-public.pem" \
  >/dev/null 2>&1 || fail 'invalid EC signing key'
cmp -s "$tmp/derived-public.pem" "$public_key" \
  || fail 'signing key does not match the tracked public release key'

"$root/scripts/check-version-sync.sh"

sdk_package="$sdk/package/$PKG_NAME"
rm -rf "$sdk_package"
mkdir -p "$sdk_package"
rsync -a --delete \
  --exclude .git \
  --exclude build \
  --exclude dist \
  --exclude .DS_Store \
  --exclude docs/local \
  "$root/" "$sdk_package/"

make -C "$sdk" defconfig
make -C "$sdk" "package/$PKG_NAME/clean" V=s
make -C "$sdk" \
  BUILD_KEY_APK_SEC="$signing_key" \
  BUILD_KEY_APK_PUB="$public_key" \
  "package/$PKG_NAME/compile" V=s

apk_tool="$sdk/staging_dir/host/bin/apk"
[ -x "$apk_tool" ] || fail "SDK apk tool not found: $apk_tool"

# The shared feed downloads the release asset by the "<package>-*.apk" glob and
# refuses a release carrying more than one match, so the name the SDK emits is
# the name that must reach the release unchanged.
package_name="${PKG_NAME}-${PKG_VERSION}.apk"
package_path="$(find "$sdk/bin/packages" -type f -name "$package_name" \
  -print -quit)"
[ -n "$package_path" ] || fail "built APK was not found: $package_name"

"$apk_tool" --allow-untrusted adbsign \
  --sign-key "$signing_key" "$package_path"
"$apk_tool" --keys-dir "$root/keys" verify "$package_path"

output="$root/dist/apk"
mkdir -p "$output"
rm -f "$output"/*.apk "$output/SHA256SUMS.apk"
cp "$package_path" "$output/$package_name"
(
  cd "$output"
  sha256sum "$package_name" >SHA256SUMS.apk
  sha256sum -c SHA256SUMS.apk >/dev/null
)

printf 'signed APK built in %s\n' "$output"
