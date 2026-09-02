# Repository Guidelines

## Start of Work

- Read `docs/MAP.md` to find the files a task touches.
- Read the sibling OpenWrt repositories' `docs/TRAPS.md` before changing LuCI
  code: the resource-cache, ACL-path and CSS-specificity traps recorded there
  apply here too.
- Run `git status -sb` and preserve unrelated changes.


## Scope

This repository contains an OpenWrt LuCI status application and its small
runtime collector. Keep monitoring read-only except for explicit per-port
firewall actions.

`docs/ARCHITECTURE.md` covers the state model, the firewall and UPnP
semantics, the localisation invariants and why the two packaging paths must
agree. `docs/OPERATIONS.md` covers releasing, the shared feed and the manual
verification recipes. Read both before changing the collector, the firewall
actions or the catalogues; several of the rules there are not derivable from
the code.

The repository is public, so tracked documentation describes the package only.
Anything tied to a particular installation — host names, deployed versions,
local paths, pending fleet work — goes in `docs/local/`, which is untracked.
Check whether it exists before assuming a router is running the latest build.

## Working rules

- Preserve OpenWrt 24.10 and 25.12 compatibility.
- Match the adjacent IKEv2 Manager LuCI layout, spacing and status semantics.
- Never expose proxy secrets or client addresses through LuCI, logs or tests.
- Treat firewall and UPnP state as security-sensitive.
- Do not restart WAN or reboot a router.
- Use UCI and firewall4; validate changes before reloading firewall4.
- Every package transaction, scripted or documented, names the package it
  touches. Never a blanket `apk upgrade`.

## Shared feed

This package is a member of `Nikitid/openwrt-feed`; the contract is
`docs/MEMBER_INTEGRATION.md` there and `Nikitid/ikev2-openwrt` is the reference
implementation. A release builds and signs only this package with the pinned SDK
and publishes it as `luci-app-mtproto-monitor-<version>.apk`. Do not add feed
assembly, a second signing key or a bootstrap installer here; point at the shared
installer instead. `scripts/check-apk-feed.sh` enforces this.

## Router-side shell

Anything installed onto a router runs against BusyBox, not GNU coreutils, and a
GNU-only option passes silently on a developer machine and in CI. Verify a
option against the target BusyBox before using it and record it in
`scripts/check-busybox-compat.sh`. Confirmed gaps: `sort -o`, `grep -P`,
`find -printf`, and no `base64` applet.

The postinst and prerm bodies exist twice, in `Makefile` and in
`scripts/stage-package.sh`. Change both; `scripts/check-packaging-parity.sh`
compares them.

## Strings

Localisation uses gettext catalogues, not translations embedded in the source.
A user-visible string is written in English and wrapped in `common.tr()`, which
calls LuCI's own `_()`. Never put a translated literal in a `.js` file.

Adding or changing a string means updating `po/templates/mtproto-monitor.pot`
and every `po/<lang>/mtproto-monitor.po`; `scripts/test-po2lmo.py` fails when
they drift from the sources or leave anything untranslated.

Two constraints are easy to violate and are checked:

- A msgid must be a single line with no repeated whitespace. `_()` normalises
  the string before hashing it, but `po2lmo` hashes the msgid verbatim, so an
  unnormalised msgid compiles into a key nothing ever looks up.
- Every entry carries `msgctxt "mtproto-monitor"`. LuCI merges all installed
  catalogues into one hash-keyed table in an unspecified order, so an
  unscoped msgid we share with another catalogue would take it over or lose to
  it. `Connections` already collides with luci-base.

`scripts/po2lmo.py` compiles the catalogues in both packaging paths; it is a
byte-compatible reimplementation of the luci-base tool, so no LuCI feed host
tools are needed. Set `PO2LMO_REFERENCE` to a real `po2lmo` binary to diff
against it. A new language also needs a display name in
`runtime/mtproto-monitor.uci-defaults`, or LuCI will never offer it.

## Validation

```sh
./scripts/ci-check.sh
```
