# Operations

Releasing this package, its place in the shared feed, and the checks that are
worth re-running by hand. Everything here has been executed against the
supported target rather than inferred.

## Release

1. Bump the version in **both** `release.env` and `Makefile`.
   `scripts/check-version-sync.sh` fails if they drift.
2. Add a `CHANGELOG.md` entry.
3. Run `./scripts/ci-check.sh`.
4. Tag `v<version>` exactly. `scripts/check-release-tag.sh` compares the tag
   against `PKG_VERSION`, so a mismatch fails the release rather than
   publishing something misnamed.

Bump the version even for a fix-only release. `apk` will not replace an
installed package with one carrying the same version, so shipping a corrected
build under the old version leaves routers on the broken one.

The release workflow builds and signs **only this package** with the pinned
OpenWrt SDK and publishes it as `luci-app-mtproto-monitor-<version>.apk`,
alongside the IPK for the 24.10 path. It does not build an index.

### The asset name is a contract

The feed collects members with the glob `<package>-*.apk` and **fails if a
release contains more than one match**. Do not add a second `.apk` asset whose
name starts with the package name. `SHA256SUMS.apk` is safe; a file such as
`luci-app-mtproto-monitor-debug.apk` would not be.

## Shared feed

The package is a member of `Nikitid/openwrt-feed`. The contract is
`docs/MEMBER_INTEGRATION.md` there; `Nikitid/ikev2-openwrt` is the reference
implementation.

- One publisher key, `keys/nikitid-openwrt-release.pem`. Its private half is
  the `OPENWRT_APK_SIGNING_KEY` Actions secret, identical across member
  repositories. `apk` binds a key to neither a package nor a repository, so a
  per-application key would only add another trust anchor to every router.
- This repository never writes to the feed. It notifies it with a
  `repository_dispatch` of type `member-release`, using
  `OPENWRT_FEED_DISPATCH_TOKEN`. The step is `continue-on-error` and exits
  cleanly when the secret is absent, because the feed also rebuilds on a daily
  schedule (`17 4 * * *` UTC) and on manual dispatch. A missing token delays
  the index; it never fails a release.

### The dispatch token is deliberately not configured

`OPENWRT_FEED_DISPATCH_TOKEN` is not set, and that is a decision rather than an
oversight. The token is an account-level credential that would have to be
copied into every member repository, and anyone who obtained a copy could write
to the feed — that is, publish packages to routers that trust the publisher
key. The only thing it buys is rebuilding the index immediately instead of at
the next scheduled run.

Trigger the rebuild explicitly instead, which needs no stored credential:

```sh
gh workflow run "Build feed" --repo Nikitid/openwrt-feed
```

This matches the feed's own design: members publish a release and nothing more,
which is what keeps their workflows free of write access to the feed. Do not
add the secret without a reason that outweighs distributing a write credential
three times over.
- Do not reintroduce feed assembly, a bootstrap installer or a second signing
  key here. `scripts/check-apk-feed.sh` fails if any of them come back.

Before setting the signing secret, confirm the private key matches the tracked
public one. Otherwise the mismatch only surfaces mid-release, after the key has
already been stored:

```sh
openssl ec -in "$PRIVATE_KEY" -pubout | cmp - keys/nikitid-openwrt-release.pem
```

## Installing on a router

Only ever name the package. There is no supported blanket upgrade:

```sh
wget -O /tmp/nikitid-feed.sh \
  https://raw.githubusercontent.com/Nikitid/openwrt-feed/feed/install.sh
sh /tmp/nikitid-feed.sh luci-app-mtproto-monitor
```

Later updates use `apk update` followed by
`apk upgrade luci-app-mtproto-monitor`.

A router that installed an earlier build by hand keeps that version until the
feed index carries a higher one; check with
`apk list --installed luci-app-mtproto-monitor`.

## Verification recipes

These are the checks that are expensive to reconstruct from scratch.

### BusyBox applets on the target

`scripts/check-busybox-compat.sh` only carries patterns confirmed against the
target build. Confirm any new one before adding it — the developer machine and
CI both provide GNU coreutils and will happily accept an option the router
ignores:

```sh
ssh <router> 'busybox sort --help; busybox grep --help; busybox find --help'
ssh <router> 'command -v base64 || echo "no base64 applet"'
```

Confirmed on BusyBox 1.37.0: `sort` takes only `[-nru]` and silently ignores
`-o`, `grep` has no `-P`, `find` has no `-printf`, and there is no `base64`
applet — use `openssl base64`.

### firewall4 defaults

The defaults that drive rule detection are readable on the router itself, which
is more reliable than documentation:

```sh
ssh <router> 'awk "/parse_rule:/,/^\t}/" /usr/share/ucode/fw4.uc | grep -E "proto|dest_port"'
ssh <router> 'awk "/parse_protocol: function/,/^\t},/" /usr/share/ucode/fw4.uc'
```

### Catalogues against the real po2lmo

`scripts/test-po2lmo.py` diffs against a reference binary when
`PO2LMO_REFERENCE` points at one. Building that binary needs one workaround:
`lib/lmo.c` includes `plural_formula.h`, which is generated by lemon at build
time, while `po2lmo.c` only needs `sfh_hash`. Compile `po2lmo.c` against that
one function extracted from `lib/lmo.c`:

```sh
cc -O1 -D__hidden= -o po2lmo po2lmo.c sfh_only.c -I.
PO2LMO_REFERENCE=./po2lmo python3 scripts/test-po2lmo.py
```

Output has been confirmed byte-identical for this package's catalogue and for
several real luci-base catalogues, including the Russian one with plural forms
and contexts.

### Catalogues against the browser

The compiler and the runtime must agree on the key. The authoritative hash is
the one in the router's own `cbi.js`; extract `s8`/`u16`/`sfh`/`trimws` from
`/www/luci-static/resources/cbi.js`, run them under node, and check that
`sfh(trimws(msgctxt) + "" + trimws(msgid))` is present in the compiled
`.lmo` and maps to the expected translation. This catches a divergence that a
C-side diff cannot.

### A published release is really signed

Use a router that already trusts the publisher key. Verification does not
install anything:

```sh
ssh <router> 'cd /tmp && wget -q -O v.apk <asset-url> && apk verify v.apk; rm -f v.apk'
```

Note that a router carrying `ikev2-manager-release.pem` already trusts this
key material: that file is a byte-identical alias kept by the IKEv2 package for
routers installed before the shared feed existed.

## Known caveats

- Routers provisioned before the shared feed may still hold
  `/etc/apk/repositories.d/ikev2-manager.list` pointing at a retired
  application feed. The shared installer retires such a list on first run, but
  only when it still holds one of those known URLs.
- Stale `status.*` directories under `/tmp/mtproto-monitor` left by versions
  before 0.2.0 are removed by the first collector run of 0.2.0 or later.

## Scope of this document

This file describes the package and is published with it, so it names no
hosts, no local paths and no deployment state. Notes about a particular
installation — which router, which version is on it, what is still pending
there — belong in `docs/local/`, which is untracked.
