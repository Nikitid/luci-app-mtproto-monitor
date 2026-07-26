# Architecture

What this package is made of and which of its rules are not obvious from the
code. Read this before changing the collector or the firewall actions.

## Components

| Path | Installed as | Role |
| --- | --- | --- |
| `runtime/mtproto-monitor.sh` | `/usr/libexec/mtproto-monitor` | Collector and firewall helper. All privileged work happens here. |
| `runtime/mtproto-monitor.init` | `/etc/init.d/mtproto-monitor` | procd service running the helper in `collect` mode. |
| `runtime/mtproto-monitor.uci-defaults` | `/etc/uci-defaults/luci-app-mtproto-monitor` | Registers bundled languages in `luci.languages`. |
| `luci/shared.js` | `.../resources/mtproto-monitor/shared.js` | Parsing, styles, translation entry point. |
| `luci/status.js` | `.../resources/view/status/mtproto-monitor.js` | The detailed page. |
| `luci/overview.js` | `.../resources/view/status/include/07_mtproto-monitor.js` | The Overview widget. |
| `luci/acl.json` | `/usr/share/rpcd/acl.d/...` | Which helper invocations each ACL group may run. |
| `po/` | `/usr/lib/lua/luci/i18n/mtproto-monitor.<lang>.lmo` | Compiled gettext catalogues. |

The browser never talks to anything but the helper, through `fs.exec`. The
helper emits `key=value` lines plus one tab-separated `instance=` line per
detected proxy; `common.parse()` is the only reader of that format.

## Runtime state

Everything lives under `/tmp/mtproto-monitor` (`umask 077`, root-owned).

- `latest` — the most recent snapshot. `status` serves it when it is younger
  than `3 * SAMPLE_INTERVAL`, otherwise it samples synchronously.
- `history.tsv` — `timestamp\tclients\tconnections`, capped at
  `HISTORY_LIMIT` (360 rows, i.e. 30 minutes at the 5 s interval).
- `status.<pid>.<random>/` — one sampling scratch directory.
- `snapshot.<pid>` — the in-progress snapshot of the collector.
- `firewall.lock/` — mutual exclusion for the firewall actions, containing
  `pid`.

**Invariant: any state named after a PID must survive that PID dying.** procd
sends SIGKILL when a package upgrade restarts the collector mid-sample, so EXIT
traps do not always run and directories do leak — leftovers from earlier
installs have been observed on a live router. Two consequences are load-bearing:

- The sample directory is created with `mktemp -d`, not `mkdir`. A directory
  named only after the PID collides once the kernel reuses that PID, and under
  `set -e` the failing `mkdir` aborts the whole sample, which surfaces as an
  empty status page.
- `prune_state` removes `status.*` and `snapshot.*` whose owner PID is no
  longer present in `/proc`, and `acquire_firewall_lock` reclaims a lock whose
  holder is gone. Without the latter a single kill leaves the open/close
  buttons permanently refusing to run.

`scripts/test-runtime.sh` reproduces the PID collision deterministically: a
wrapper shell creates `status.$$` and then `exec`s the helper, so the helper
runs under exactly the PID the directory was named for.

## Firewall semantics

Detection and mutation are deliberately asymmetric.

**Detection is wide.** firewall4 treats an unset field as a widening, not a
narrowing. From `/usr/share/ucode/fw4.uc` on the target:

- `proto: [ "protocol", "tcpudp", ... ]` — an unset `proto` covers TCP.
- `dest_port: [ "port", null, ... ]` — an unset `dest_port` covers every port.
- `parse_protocol` maps `all`, `any`, `*`, `6` and `tcpudp` onto TCP too.

`proto_covers_tcp` and `firewall_rule_matches` follow those rules. Requiring a
literal `tcp` and a non-empty port list made the page report "WAN closed" for a
port WAN could actually reach, which is the worst direction for this error.

**Mutation is narrow.** `firewall-close` refuses any rule that is not an exact
single-port TCP match and says so, rather than editing a shared or ranged rule
that other services may depend on. `firewall-open` only re-enables a rule it
could have created itself. Every change runs `fw4 check` first and restores the
exported UCI backup if `fw4 reload` fails.

## UPnP reservation

miniupnpd applies `perm_rule` entries in order and the **first** rule whose
external port range covers the request decides. `upnp_reserved` mirrors that:
it stops at the first covering rule and reports reserved only when that rule is
a `deny`. Scanning the whole list for any `deny` reported a reservation that an
earlier `allow` had already overridden.

## LuCI layer

- `poll.add` deduplicates by function reference, so registering the same
  `refreshPage` twice is a no-op. No extra guard is needed.
- The read ACL group needs both the `file` exec paths **and** `ubus file exec`.
  Without the latter a read-only session cannot call the helper at all.
- Per-instance action results expire (`feedbackTimeout`). The table is rebuilt
  on every poll, so a result with no expiry would sit under the row until the
  page was reloaded.
- Nothing derived from proxy configuration reaches the DOM as markup; all
  values become text nodes. Client addresses and proxy secrets never leave the
  helper — the helper aggregates remote addresses into counts and discards them.

## Localisation

Catalogues are gettext, compiled to LuCI's LMO format and looked up through the
stock `_()` in `cbi.js`. `common.tr()` is a thin wrapper that supplies the
context. Two invariants are easy to break and are both tested:

- **msgids must already be whitespace-normalised.** `_()` applies
  `trimws()` (trim, then collapse runs of space/tab/newline) *before* hashing,
  while `po2lmo` hashes the msgid verbatim. An unnormalised msgid compiles into
  a key nothing ever looks up.
- **Every entry carries `msgctxt "mtproto-monitor"`.** LuCI merges every
  installed catalogue into one hash-keyed `window.TR` table in an unspecified
  order. An unscoped msgid shared with another catalogue either loses to it or
  silently takes it over. `Connections` already collides with luci-base, which
  translates it as "Соединения" where this page means "Подключения". The
  context makes each key ours alone.

This is a deliberate departure from the sibling applications, which use plain
msgids and resolve collisions by copying luci-base's exact wording. That works
only for as long as nobody edits either side.

`scripts/po2lmo.py` is a byte-compatible reimplementation of the luci-base
tool, so neither packaging path depends on the LuCI feed host utilities.

## Packaging

The package is built two ways and both must agree:

- `Makefile` — the OpenWrt SDK path, used for the signed APK.
- `scripts/stage-package.sh` — the SDK-less path, used for the IPK.

Each carries its own copy of the file list and of the postinst/prerm bodies,
and nothing in the language forces them to match.
`scripts/check-packaging-parity.sh` compares both, after normalising the `$$`
that make collapses to `$`. It has already caught a one-sided edit.

The IPK build is required to be reproducible: `scripts/ci-check.sh` builds it
twice and compares SHA-256. Anything that enters the package must therefore be
deterministic, which is why the compiled catalogues get an explicit `chmod 644`
(`po2lmo.py` otherwise honours the caller's umask).

Because the package defines its own postinst, the default handler that drains
`/etc/uci-defaults` does not run; the postinst invokes the language
registration itself so a runtime install takes effect without a reboot.
