# Repository map

Where things live, so a task starts at the right file. The largest source file
is 849 lines, so no generated index is warranted; read the part you need.

## The shape of it

One OpenWrt package, `luci-app-mtproto-monitor`: a status page for local
Telegram MTProto proxies, plus per-instance control of whether their TCP port
is reachable from WAN.

| area | files |
| --- | --- |
| runtime | `runtime/mtproto-monitor.sh`, its init script and uci-defaults |
| pages | `luci/overview.js`, `luci/status.js` |
| shared design system and dictionary | `luci/shared.js` |
| wiring | `luci/menu.json`, `luci/acl.json` |
| translations | `po/`, built by `scripts/po2lmo.py` |
| build and release | `Makefile`, `apk-feed.env`, `release.env`, `scripts/` |

Three proxy implementations are supported: the Go `tg-ws-proxy`, the older
`tg-ws-proxy-go`/SOCKS5 and the Rust `tg-ws-proxy-rs`.

## Rules the runtime is built on

Client addresses and proxy secrets never reach LuCI, a log line or a test
fixture. Firewall changes are validated with `fw4 check` before they are kept,
and the previous configuration is restored when that fails.

## Checks

`scripts/ci-check.sh` runs everything: version sync, packaging parity, the
BusyBox compatibility check, the public-tree check, and the runtime, firewall
and translation tests.

## Documentation

| file | for |
| --- | --- |
| `AGENTS.md` | the rules of working here |
| `docs/MAP.md` | this file |
| `docs/ARCHITECTURE.md` | how the monitor and the firewall control work |
| `docs/OPERATIONS.md` | installing and releasing |
| `README.md` | operator-facing, Russian |
| `README.en.md` | the English version |
