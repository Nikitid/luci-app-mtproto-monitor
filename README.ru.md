# MTProto Monitor для OpenWrt

[English](README.md)

[![CI](https://github.com/Nikitid/luci-app-mtproto-monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/Nikitid/luci-app-mtproto-monitor/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Nikitid/luci-app-mtproto-monitor)](https://github.com/Nikitid/luci-app-mtproto-monitor/releases/latest)
[![Лицензия: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Пакет `luci-app-mtproto-monitor` - небольшое LuCI-приложение для наблюдения за
локальными Telegram-прокси и управления доступом к ним из WAN.

## Возможности

- активные клиенты, TCP-подключения, история за 30 минут и состояние каждого
  найденного прокси;
- поддерживаются `tg-ws-proxy` на Go, старый `tg-ws-proxy-go`/SOCKS5 и
  `tg-ws-proxy-rs` на Rust;
- TCP-порт каждого экземпляра можно явно открыть или закрыть из WAN; перед
  применением выполняется `fw4 check`, при ошибке конфигурация
  восстанавливается;
- адреса клиентов и секреты не выводятся и не сохраняются.

## Требования

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
обновления - тем же адресным вызовом:

```sh
apk update
apk upgrade luci-app-mtproto-monitor
```

Обновление всего роутера (`apk upgrade` без имени пакета) не требуется и не
предполагается.

### OpenWrt 24.10

Скачайте `luci-app-mtproto-monitor_*_all.ipk` из
[Releases](https://github.com/Nikitid/luci-app-mtproto-monitor/releases) и установите
через **System -> Software -> Upload Package**.

После установки откройте **Status -> Overview** или
**Status -> MTProto Monitor**. Установка не меняет firewall автоматически.

## Подсчёт клиентов

Клиент - уникальный удалённый адрес среди установленных TCP-соединений прокси.
Несколько пользователей за одним NAT могут считаться одним клиентом.

## Разработка

```sh
./scripts/ci-check.sh
```

Выпуск и работа с фидом: [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Документация

- [Карта репозитория](docs/MAP.md) - где что лежит
- [Архитектура](docs/ARCHITECTURE.md) - компоненты, состояние, правила firewall, упаковка
- [Эксплуатация](docs/OPERATIONS.md) - выпуск релиза, фид, установка и проверки на роутере

## Поддержка

Вопросы и сообщения об ошибках - в
[Issues](https://github.com/Nikitid/luci-app-mtproto-monitor/issues/new/choose), выберите
подходящую форму. Об уязвимости сообщайте приватно через
[security advisory](https://github.com/Nikitid/luci-app-mtproto-monitor/security/advisories/new).
Можно писать по-русски или по-английски.

## Лицензия

[MIT](LICENSE)
