include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-mtproto-monitor
PKG_VERSION:=0.1.0
PKG_RELEASE:=
PKG_LICENSE:=MIT
PKG_MAINTAINER:=nikitid
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-mtproto-monitor
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=2. Modules
  TITLE:=MTProto Monitor for OpenWrt
  URL:=https://github.com/nikitid/mtproto-monitor
  DEPENDS:=+luci-base +rpcd-mod-file +firewall4
endef

define Package/luci-app-mtproto-monitor/description
 LuCI status page and Overview widget for monitoring active clients and
 connections of supported Telegram proxy implementations on OpenWrt.
endef

define Build/Compile
endef

define Package/luci-app-mtproto-monitor/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./runtime/mtproto-monitor.init $(1)/etc/init.d/mtproto-monitor

	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./runtime/mtproto-monitor.sh $(1)/usr/libexec/mtproto-monitor

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./luci/menu.json $(1)/usr/share/luci/menu.d/luci-app-mtproto-monitor.json
	$(INSTALL_DATA) ./luci/acl.json $(1)/usr/share/rpcd/acl.d/luci-app-mtproto-monitor.json

	$(INSTALL_DIR) $(1)/www/luci-static/resources/mtproto-monitor
	$(INSTALL_DATA) ./luci/shared.js $(1)/www/luci-static/resources/mtproto-monitor/shared.js

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/status
	$(INSTALL_DATA) ./luci/status.js $(1)/www/luci-static/resources/view/status/mtproto-monitor.js

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/status/include
	$(INSTALL_DATA) ./luci/overview.js $(1)/www/luci-static/resources/view/status/include/07_mtproto-monitor.js

	$(INSTALL_DIR) $(1)/usr/share/licenses/luci-app-mtproto-monitor
	$(INSTALL_DATA) ./LICENSE $(1)/usr/share/licenses/luci-app-mtproto-monitor/LICENSE
endef

define Package/luci-app-mtproto-monitor/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
rm -f /www/luci-static/resources/view/status/include/70_mtproto-monitor.js
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
/etc/init.d/mtproto-monitor enable >/dev/null 2>&1 || true
/etc/init.d/mtproto-monitor restart >/dev/null 2>&1 || true
echo "MTProto Monitor installed. Open LuCI -> Status -> MTProto Monitor."
exit 0
endef

define Package/luci-app-mtproto-monitor/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
case "$${1:-}" in upgrade) exit 0 ;; esac
[ "$${PKG_UPGRADE:-0}" = 1 ] && exit 0
/etc/init.d/mtproto-monitor stop >/dev/null 2>&1 || true
/etc/init.d/mtproto-monitor disable >/dev/null 2>&1 || true
rm -rf /tmp/mtproto-monitor
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
exit 0
endef

$(eval $(call BuildPackage,luci-app-mtproto-monitor))
