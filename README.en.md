# MTProto Monitor for OpenWrt

[Русский](README.md)

A small LuCI application for local Telegram proxies. It reports active clients,
TCP connections, 30-minute aggregate history and per-proxy health without
returning or storing client addresses or proxy secrets.

Supported layouts are packaged Go `tg-ws-proxy`, legacy
`tg-ws-proxy-go`/SOCKS5 and Rust `tg-ws-proxy-rs`. WAN access can be opened or
closed explicitly for each detected proxy port. Changes are validated with
`fw4 check` and rolled back on failure.

## Compatibility

- official OpenWrt `24.10.x` with `opkg`;
- official OpenWrt `25.12.x` with `apk`;
- LuCI and firewall4/nftables.

The package is a member of the shared signed feed
[Nikitid/openwrt-feed](https://github.com/Nikitid/openwrt-feed) and is built for
OpenWrt `25.12.5`, `mediatek/filogic`, `aarch64_cortex-a53`.

## Installation

For OpenWrt 25.12:

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

For OpenWrt 24.10, download the `*_all.ipk` package from
[Releases](https://github.com/Nikitid/luci-mtproto/releases) and install it
through `System -> Software -> Upload Package`.

Installation does not change firewall rules automatically.

Open `Status -> Overview` or `Status -> MTProto Monitor` after installation.

## Validation

```sh
./scripts/ci-check.sh
```

## License

[MIT](LICENSE)
