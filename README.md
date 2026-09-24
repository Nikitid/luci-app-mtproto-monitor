# MTProto Monitor for OpenWrt

[Русский](README.ru.md)

[![CI](https://github.com/Nikitid/luci-app-mtproto-monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/Nikitid/luci-app-mtproto-monitor/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Nikitid/luci-app-mtproto-monitor)](https://github.com/Nikitid/luci-app-mtproto-monitor/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

The `luci-app-mtproto-monitor` package is a small LuCI application for watching
local Telegram proxies and controlling their WAN exposure.

## Features

- active clients, TCP connections, 30-minute history and the health of each
  detected proxy;
- supports packaged Go `tg-ws-proxy`, legacy `tg-ws-proxy-go`/SOCKS5 and
  Rust `tg-ws-proxy-rs`;
- WAN access can be opened or closed explicitly for each proxy port; changes
  are validated with `fw4 check` and rolled back on failure;
- client addresses and proxy secrets are never returned or stored.

## Requirements

- official OpenWrt `24.10.x` with `opkg`;
- official OpenWrt `25.12.x` with `apk`;
- LuCI and firewall4/nftables.

The package is a member of the shared signed feed
[Nikitid/openwrt-feed](https://github.com/Nikitid/openwrt-feed) and is built for
OpenWrt `25.12.5`, `mediatek/filogic`, `aarch64_cortex-a53`.

## Installation

### OpenWrt 25.12

```sh
wget -O /tmp/nikitid-feed.sh \
  https://raw.githubusercontent.com/Nikitid/openwrt-feed/feed/install.sh
sh /tmp/nikitid-feed.sh luci-app-mtproto-monitor
```

The installer verifies the publisher public key against a pinned checksum,
configures one shared feed entry and installs only the packages it is given.
Later updates use the same targeted call:

```sh
apk update
apk upgrade luci-app-mtproto-monitor
```

Upgrading the whole router (`apk upgrade` with no package name) is neither
required nor intended.

### OpenWrt 24.10

Download `luci-app-mtproto-monitor_*_all.ipk` from
[Releases](https://github.com/Nikitid/luci-app-mtproto-monitor/releases) and install it
through **System -> Software -> Upload Package**.

Open **Status -> Overview** or **Status -> MTProto Monitor** after installation.
Installation does not change firewall rules automatically.

## Counting clients

A client is a unique remote address among the proxy's established TCP
connections. Several users behind one NAT may count as one client.

## Development

```sh
./scripts/ci-check.sh
```

Releasing and working with the feed: [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Documentation

- [Repository map](docs/MAP.md) - where things live
- [Architecture](docs/ARCHITECTURE.md) - components, state, firewall rules, packaging
- [Operations](docs/OPERATIONS.md) - releases, the feed, installing and verifying on a router

## Support

Questions and bug reports go to
[Issues](https://github.com/Nikitid/luci-app-mtproto-monitor/issues/new/choose): pick the form that
fits. Report a vulnerability privately through
[a security advisory](https://github.com/Nikitid/luci-app-mtproto-monitor/security/advisories/new).
English or Russian is fine.

## License

[MIT](LICENSE)
