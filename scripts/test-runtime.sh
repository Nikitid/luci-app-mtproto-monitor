#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/etc/init.d" "$tmp/etc/tg-ws-proxy" "$tmp/usr/bin"
mkdir -p "$tmp/proc/net" "$tmp/proc/101/fd" "$tmp/proc/202/fd"
touch "$tmp/usr/bin/tg-ws-proxy" "$tmp/usr/bin/tg-ws-proxy-rs"
ln -s "$tmp/usr/bin/tg-ws-proxy" "$tmp/proc/101/exe"
ln -s "$tmp/usr/bin/tg-ws-proxy-rs" "$tmp/proc/202/exe"
ln -s 'socket:[1001]' "$tmp/proc/101/fd/3"
ln -s 'socket:[1002]' "$tmp/proc/101/fd/4"
ln -s 'socket:[1003]' "$tmp/proc/101/fd/5"
ln -s 'socket:[2001]' "$tmp/proc/202/fd/3"
ln -s 'socket:[2002]' "$tmp/proc/202/fd/4"
printf '%s\0%s\0%s\0' "$tmp/usr/bin/tg-ws-proxy" --port 1443 >"$tmp/proc/101/cmdline"
printf '%s\0%s\0%s\0' "$tmp/usr/bin/tg-ws-proxy-rs" --port 2443 >"$tmp/proc/202/cmdline"

cat >"$tmp/proc/net/tcp" <<'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000:05A3 00000000:0000 0A 00000000:00000000 00:00000000 00000000 0 0 1001
   1: 0100007F:05A3 0100000A:C001 01 00000000:00000000 00:00000000 00000000 0 0 1002
   2: 0100007F:05A3 0100000A:C003 01 00000000:00000000 00:00000000 00000000 0 0 1003
   3: 00000000:098B 00000000:0000 0A 00000000:00000000 00:00000000 00000000 0 0 2001
   4: 0100007F:098B 0100000A:C002 01 00000000:00000000 00:00000000 00000000 0 0 2002
EOF
cat >"$tmp/proc/net/tcp6" <<'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
EOF

cat >"$tmp/uci" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 755 "$tmp/uci"

output="$(
  MTPROTO_MONITOR_ETC_ROOT="$tmp/etc" \
    MTPROTO_MONITOR_PROC_ROOT="$tmp/proc" \
    MTPROTO_MONITOR_USR_ROOT="$tmp/usr" \
    MTPROTO_MONITOR_STATE_DIR="$tmp/state" \
    MTPROTO_MONITOR_UCI="$tmp/uci" \
    "$root/runtime/mtproto-monitor.sh" status
)"

printf '%s\n' "$output" | grep -q '^installed=2$'
printf '%s\n' "$output" | grep -q '^running=2$'
printf '%s\n' "$output" | grep -q '^listening=2$'
printf '%s\n' "$output" | grep -q '^clients=1$'
printf '%s\n' "$output" | grep -q '^connections=3$'
printf '%s\n' "$output" | grep -q '^instance=go	.*	1	2	'
printf '%s\n' "$output" | grep -q '^instance=go	'
printf '%s\n' "$output" | grep -q '^instance=rust	'
! printf '%s\n' "$output" | grep -q '0100000A'

run_status() {
  MTPROTO_MONITOR_ETC_ROOT="$tmp/etc" \
    MTPROTO_MONITOR_PROC_ROOT="$tmp/proc" \
    MTPROTO_MONITOR_USR_ROOT="$tmp/usr" \
    MTPROTO_MONITOR_STATE_DIR="$tmp/state" \
    MTPROTO_MONITOR_UCI="$tmp/uci" \
    "$root/runtime/mtproto-monitor.sh" status
}

# procd sends SIGKILL when a package upgrade restarts the collector mid-sample,
# so sample directories do leak. Once the kernel reuses that PID, a sample
# directory named only after the PID already exists and the sample fails.
# The wrapper below execs the helper, so the helper runs under the very PID the
# wrapper prepared a directory for.
rm -rf "$tmp/state"
mkdir -p "$tmp/state"
MTPROTO_MONITOR_ETC_ROOT="$tmp/etc" \
  MTPROTO_MONITOR_PROC_ROOT="$tmp/proc" \
  MTPROTO_MONITOR_USR_ROOT="$tmp/usr" \
  MTPROTO_MONITOR_STATE_DIR="$tmp/state" \
  MTPROTO_MONITOR_UCI="$tmp/uci" \
  sh -c '
  mkdir -p "$1/status.$$"
  exec "$2" status
' _ "$tmp/state" "$root/runtime/mtproto-monitor.sh" \
  >"$tmp/collide.out" 2>"$tmp/collide.err" \
  || {
    printf 'a reused PID broke the status sample\n' >&2
    cat "$tmp/collide.err" >&2
    exit 1
  }
grep -q '^installed=2$' "$tmp/collide.out" || {
  printf 'the status sample produced no data under a reused PID\n' >&2
  exit 1
}

# Leaked state is pruned by owner liveness, and state a live process owns stays.
rm -rf "$tmp/state"
mkdir -p "$tmp/state"
mkdir "$tmp/state/status.999999"
: >"$tmp/state/snapshot.999999"
mkdir "$tmp/state/status.101.abcdef"
: >"$tmp/state/snapshot.101"
run_status >/dev/null
[ ! -e "$tmp/state/status.999999" ] || {
  printf 'a leaked sample directory was kept\n' >&2
  exit 1
}
[ ! -e "$tmp/state/snapshot.999999" ] || {
  printf 'a leaked snapshot file was kept\n' >&2
  exit 1
}
[ -d "$tmp/state/status.101.abcdef" ] || {
  printf 'state owned by a live process was removed\n' >&2
  exit 1
}
[ -e "$tmp/state/snapshot.101" ] || {
  printf 'a snapshot owned by a live process was removed\n' >&2
  exit 1
}

# An empty history is the normal state after boot, not a helper failure.
rm -rf "$tmp/state"
MTPROTO_MONITOR_ETC_ROOT="$tmp/etc" \
  MTPROTO_MONITOR_PROC_ROOT="$tmp/proc" \
  MTPROTO_MONITOR_USR_ROOT="$tmp/usr" \
  MTPROTO_MONITOR_STATE_DIR="$tmp/state" \
  MTPROTO_MONITOR_UCI="$tmp/uci" \
  "$root/runtime/mtproto-monitor.sh" history >"$tmp/history.out" || {
  printf 'an empty history was reported as a helper failure\n' >&2
  exit 1
}
[ ! -s "$tmp/history.out" ]

printf 'test-runtime OK\n'
