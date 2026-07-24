# MTProto Monitor для OpenWrt

[English](README.en.md)

[![CI](https://github.com/Nikitid/mtproto-monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/Nikitid/mtproto-monitor/actions/workflows/ci.yml)
[![Лицензия: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Небольшое LuCI-приложение для локальных Telegram-прокси. Показывает активных
клиентов, TCP-подключения, историю за 30 минут и состояние каждого найденного
прокси. Адреса клиентов и секреты не выводятся и не сохраняются.

Поддерживаются `tg-ws-proxy` на Go, старый `tg-ws-proxy-go`/SOCKS5 и
`tg-ws-proxy-rs` на Rust. Для каждого экземпляра можно явно открыть или закрыть
его TCP-порт из WAN. Перед применением выполняется `fw4 check`, при ошибке
конфигурация восстанавливается.

## Совместимость

- официальный OpenWrt `24.10.x` с `opkg`;
- официальный OpenWrt `25.12.x` с `apk`;
- LuCI и firewall4/nftables.

Подписанный APK-feed проверен для OpenWrt `25.12.5`, `mediatek/filogic`,
`aarch64_cortex-a53`.

## Установка

### OpenWrt 24.10

Скачайте `luci-app-mtproto-monitor_*_all.ipk` из
[Releases](https://github.com/Nikitid/mtproto-monitor/releases) и установите
через `System -> Software -> Upload Package`.

### OpenWrt 25.12

```sh
wget -O /tmp/install-mtproto-monitor.sh \
  https://github.com/Nikitid/mtproto-monitor/releases/latest/download/install-openwrt25.sh
sh /tmp/install-mtproto-monitor.sh
```

Установщик проверяет публичный ключ релиза, подключает подписанный APK-feed и
проверяет транзакцию перед установкой. Последующие обновления:

```sh
apk update
apk upgrade luci-app-mtproto-monitor
```

После установки откройте `Status -> Overview` или
`Status -> MTProto Monitor`. Установка не меняет firewall автоматически.

## Подсчёт клиентов

Клиент — уникальный удалённый адрес среди установленных TCP-соединений прокси.
Несколько пользователей за одним NAT могут считаться одним клиентом.

## Проверка

```sh
./scripts/ci-check.sh
```

## Лицензия

[MIT](LICENSE)
