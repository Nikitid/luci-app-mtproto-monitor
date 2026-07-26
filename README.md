# MTProto Monitor для OpenWrt

[English](README.en.md)

[![CI](https://github.com/Nikitid/luci-mtproto/actions/workflows/ci.yml/badge.svg)](https://github.com/Nikitid/luci-mtproto/actions/workflows/ci.yml)
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

Пакет входит в общий подписанный фид
[Nikitid/openwrt-feed](https://github.com/Nikitid/openwrt-feed) и собирается
для OpenWrt `25.12.5`, `mediatek/filogic`, `aarch64_cortex-a53`.

## Установка

### OpenWrt 25.12

```sh
wget -O /tmp/nikitid-feed.sh \
  https://raw.githubusercontent.com/Nikitid/openwrt-feed/feed/install.sh
sh /tmp/nikitid-feed.sh luci-app-mtproto-monitor
```

Установщик проверяет публичный ключ издателя по закреплённой контрольной сумме,
подключает один общий фид и устанавливает только названные пакеты. Последующие
обновления — тем же адресным вызовом:

```sh
apk update
apk upgrade luci-app-mtproto-monitor
```

Обновление всего роутера (`apk upgrade` без имени пакета) не требуется и не
предполагается.

### OpenWrt 24.10

Скачайте `luci-app-mtproto-monitor_*_all.ipk` из
[Releases](https://github.com/Nikitid/luci-mtproto/releases) и установите
через `System -> Software -> Upload Package`.

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
