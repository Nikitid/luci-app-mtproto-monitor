# Changelog

## 0.2.0

- Join the shared signed feed `Nikitid/openwrt-feed` and use the shared
  publisher key `keys/nikitid-openwrt-release.pem`. The per-application key and
  per-application feed are gone; no router trusted them, so no rotation was
  needed.
- Build and sign only this package on a release and publish it as
  `luci-app-mtproto-monitor-<version>.apk`. The signed index is assembled by the
  feed repository, so a release no longer depends on a sibling application.
- Replace the bundled bootstrap installer with the shared feed installer. Every
  documented package transaction names the package it touches.
- Report WAN access correctly for rules that leave `proto` or `dest_port` unset.
  firewall4 reads an unset field as "tcpudp" and "any port", so such a rule does
  reach the proxy port; the page previously showed "WAN closed" for it.
- Report a UPnP reservation the way miniupnpd resolves one: the first perm_rule
  covering the port decides, and a range counts as well as a single port. A deny
  shadowed by an earlier allow no longer reads as reserved.
- Keep the status page working after a sample directory leaks. A directory named
  only after the caller PID collided once that PID was reused and failed the
  whole sample; leaked state is now pruned by owner liveness.
- Reclaim a firewall lock left behind by a killed process instead of refusing
  every later open or close action.
- Grant `ubus file exec` to the read ACL group, so a read-only session can list
  instances at all.
- Report an empty history as empty rather than as a failed helper call.
- Colour the activity legend markers to match their chart lines, and expire the
  per-instance action result instead of leaving it under the row.
- Move localisation to gettext catalogues compiled into LuCI's LMO format and
  looked up through the stock `_()`, replacing translations embedded in the
  JavaScript. Strings can now be translated with standard tooling, and the
  language follows the one configured in LuCI rather than a guess. Every entry
  is scoped by `msgctxt`, because `Connections` collides with luci-base, which
  translates it differently; catalogues merge in an unspecified order, so an
  unscoped collision would silently rewrite the other catalogue's entry.
- Compile catalogues with a bundled byte-compatible `po2lmo`, so both packaging
  paths ship identical catalogues without the LuCI feed host tools.
- Register bundled languages in `luci.languages`, without which LuCI never
  offers them.
- Check shipped shell for BusyBox gaps (`sort -o`, `grep -P`, `find -printf`,
  the missing `base64` applet) and check that both packaging paths install the
  same files and the same maintainer scripts.

## 0.1.0

- Add a dedicated LuCI status page and an OpenWrt Overview widget.
- Add an IKEv2-style quick-link button from Overview to the detailed monitor.
- Count unique active clients without exposing or storing their addresses.
- Track active TCP connections and sanitized 30-minute aggregate history.
- Detect packaged Go, legacy Go/SOCKS5 and Rust proxy layouts.
- Report listener, WAN firewall and UPnP reservation state.
- Add per-proxy WAN open/close actions with firewall4 validation and rollback.
- Refuse unsafe automatic edits to shared or ranged firewall rules.
- Install the Overview widget as `07_mtproto-monitor.js`.
- Add deterministic IPK and OpenWrt SDK APK build paths.
