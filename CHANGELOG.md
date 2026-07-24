# Changelog

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
