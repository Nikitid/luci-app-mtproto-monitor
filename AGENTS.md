# Repository Guidelines

## Scope

This repository contains an OpenWrt LuCI status application and its small
runtime collector. Keep monitoring read-only except for explicit per-port
firewall actions.

## Working rules

- Preserve OpenWrt 24.10 and 25.12 compatibility.
- Match the adjacent IKEv2 Manager LuCI layout, spacing and status semantics.
- Never expose proxy secrets or client addresses through LuCI, logs or tests.
- Treat firewall and UPnP state as security-sensitive.
- Do not restart WAN or reboot a router.
- Use UCI and firewall4; validate changes before reloading firewall4.

## Validation

```sh
./scripts/ci-check.sh
```
