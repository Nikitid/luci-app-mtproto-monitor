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

The signed APK feed is validated on OpenWrt `25.12.5`,
`mediatek/filogic`, `aarch64_cortex-a53`.

## Installation

For OpenWrt 24.10, download the `*_all.ipk` package from
[Releases](https://github.com/Nikitid/mtproto-monitor/releases) and install it
through `System -> Software -> Upload Package`.

For OpenWrt 25.12:

```sh
wget -O /tmp/install-mtproto-monitor.sh \
  https://github.com/Nikitid/mtproto-monitor/releases/latest/download/install-openwrt25.sh
sh /tmp/install-mtproto-monitor.sh
```

The installer verifies the release public key, configures the signed APK feed
and simulates the package transaction before installation. Installation does
not change firewall rules automatically.

Open `Status -> Overview` or `Status -> MTProto Monitor` after installation.

## Validation

```sh
./scripts/ci-check.sh
```

## License

[MIT](LICENSE)
