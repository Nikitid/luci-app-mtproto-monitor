#!/bin/sh

set -eu

[ "$#" -eq 1 ] || {
  printf 'Usage: %s STAGE\n' "$0" >&2
  exit 2
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
stage="$1"
. "$root/release.env"

rm -rf "$stage"
mkdir -p "$stage/CONTROL"

install_file() {
  mode="$1"
  source="$root/$2"
  target="$stage$3"
  mkdir -p "${target%/*}"
  install -m "$mode" "$source" "$target"
}

install_file 755 runtime/mtproto-monitor.init /etc/init.d/mtproto-monitor
install_file 755 runtime/mtproto-monitor.sh /usr/libexec/mtproto-monitor
install_file 755 runtime/mtproto-monitor.uci-defaults /etc/uci-defaults/luci-app-mtproto-monitor
install_file 644 luci/menu.json /usr/share/luci/menu.d/luci-app-mtproto-monitor.json
install_file 644 luci/acl.json /usr/share/rpcd/acl.d/luci-app-mtproto-monitor.json
install_file 644 luci/shared.js /www/luci-static/resources/mtproto-monitor/shared.js
install_file 644 luci/status.js /www/luci-static/resources/view/status/mtproto-monitor.js
install_file 644 luci/overview.js /www/luci-static/resources/view/status/include/07_mtproto-monitor.js
install_file 644 LICENSE /usr/share/licenses/luci-app-mtproto-monitor/LICENSE

# scripts/po2lmo.py is a byte-compatible reimplementation of the luci-base
# po2lmo tool, so this SDK-less path produces the same catalogues as the
# SDK-built APK without depending on the LuCI feed host tools.
mkdir -p "$stage/usr/lib/lua/luci/i18n"
for po in "$root"/po/*/*.po; do
  [ -f "$po" ] || continue
  language="$(basename "$(dirname "$po")")"
  [ "$language" != templates ] || continue
  catalog="$stage/usr/lib/lua/luci/i18n/$(basename "$po" .po).$language.lmo"
  python3 "$root/scripts/po2lmo.py" "$po" "$catalog"
  # po2lmo.py honours the caller's umask; fix the mode so the packaged file
  # stays byte-identical across build hosts.
  chmod 644 "$catalog"
done

version="$PKG_VERSION"
[ -z "$PKG_RELEASE" ] || version="$version-r$PKG_RELEASE"
cat >"$stage/CONTROL/control" <<EOF
Package: $PKG_NAME
Version: $version
Depends: luci-base, rpcd-mod-file, firewall4
Section: luci
Architecture: $PKG_ARCH
Maintainer: nikitid
Homepage: https://github.com/Nikitid/luci-app-mtproto-monitor
Description: MTProto Monitor for OpenWrt
 LuCI status page and Overview widget for active Telegram proxy clients and
 connections. Supports package Go, legacy Go/SOCKS5 and Rust layouts.
EOF

cat >"$stage/CONTROL/postinst" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
rm -f /www/luci-static/resources/view/status/include/70_mtproto-monitor.js
# This package defines its own postinst, so the default handler that drains
# /etc/uci-defaults does not run. Register the bundled catalogues here, so a
# runtime install takes effect without waiting for the next boot.
if [ -x /etc/uci-defaults/luci-app-mtproto-monitor ]; then
	/etc/uci-defaults/luci-app-mtproto-monitor &&
		rm -f /etc/uci-defaults/luci-app-mtproto-monitor
fi
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
/etc/init.d/mtproto-monitor enable >/dev/null 2>&1 || true
/etc/init.d/mtproto-monitor restart >/dev/null 2>&1 || true
echo "MTProto Monitor installed. Open LuCI -> Status -> MTProto Monitor."
exit 0
EOF

cat >"$stage/CONTROL/prerm" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
case "${1:-}" in upgrade) exit 0 ;; esac
[ "${PKG_UPGRADE:-0}" = 1 ] && exit 0
/etc/init.d/mtproto-monitor stop >/dev/null 2>&1 || true
/etc/init.d/mtproto-monitor disable >/dev/null 2>&1 || true
rm -rf /tmp/mtproto-monitor
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
exit 0
EOF
chmod 755 "$stage/CONTROL/postinst" "$stage/CONTROL/prerm"
