#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/apk-feed.env"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/bin" "$tmp/root/etc"
cat >"$tmp/bin/wget" <<'EOF'
#!/bin/sh
cp "$TEST_APK_KEY" "$3"
EOF
cat >"$tmp/bin/apk" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$TEST_APK_LOG"
[ "$1" != info ] || exit 1
[ "${TEST_APK_FAIL_UPDATE:-0}" != 1 ] || [ "$1" != update ] || exit 1
EOF

new_root() {
  test_root="$1"
  mkdir -p "$test_root/etc"
  cat >"$test_root/etc/openwrt_release" <<'EOF'
DISTRIB_ID='OpenWrt'
DISTRIB_RELEASE='25.12.5'
DISTRIB_TARGET='mediatek/filogic'
DISTRIB_ARCH='aarch64_cortex-a53'
EOF
}

new_root "$tmp/root"
chmod 755 "$tmp/bin/wget" "$tmp/bin/apk"
: >"$tmp/apk.log"

PATH="$tmp/bin:$PATH" \
  TEST_APK_KEY="$root/$OPENWRT_APK_KEY_FILE" \
  TEST_APK_LOG="$tmp/apk.log" \
  MTPROTO_INSTALL_ROOT="$tmp/root" \
  "$root/scripts/install-openwrt25.sh" >/dev/null

[ "$(sha256sum "$tmp/root/etc/apk/keys/mtproto-monitor-release.pem" \
  | awk '{ print $1 }')" = "$OPENWRT_APK_TRUST_SHA256" ]
[ "$(cat "$tmp/root/etc/apk/repositories.d/mtproto-monitor.list")" = \
  "$OPENWRT_APK_FEED_URL" ]
grep -qx 'update' "$tmp/apk.log"
grep -qx 'add --simulate luci-app-mtproto-monitor' "$tmp/apk.log"
grep -qx 'add luci-app-mtproto-monitor' "$tmp/apk.log"

failure_root="$tmp/failure"
new_root "$failure_root"
: >"$tmp/failure.log"
if PATH="$tmp/bin:$PATH" \
  TEST_APK_KEY="$root/$OPENWRT_APK_KEY_FILE" \
  TEST_APK_LOG="$tmp/failure.log" \
  TEST_APK_FAIL_UPDATE=1 \
  MTPROTO_INSTALL_ROOT="$failure_root" \
  "$root/scripts/install-openwrt25.sh" >/dev/null 2>&1; then
  printf 'failed APK update was accepted\n' >&2
  exit 1
fi
[ ! -e "$failure_root/etc/apk/keys/mtproto-monitor-release.pem" ]
[ ! -e "$failure_root/etc/apk/repositories.d/mtproto-monitor.list" ]

wrong_target_root="$tmp/wrong-target"
new_root "$wrong_target_root"
sed -i.bak "s|mediatek/filogic|ath79/generic|" \
  "$wrong_target_root/etc/openwrt_release"
if PATH="$tmp/bin:$PATH" \
  TEST_APK_KEY="$root/$OPENWRT_APK_KEY_FILE" \
  TEST_APK_LOG="$tmp/wrong-target.log" \
  MTPROTO_INSTALL_ROOT="$wrong_target_root" \
  "$root/scripts/install-openwrt25.sh" >/dev/null 2>&1; then
  printf 'unsupported target was accepted\n' >&2
  exit 1
fi

printf 'test-apk-bootstrap OK\n'
