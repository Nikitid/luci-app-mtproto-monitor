#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/etc/tg-ws-proxy" "$tmp/usr/bin" "$tmp/proc/net" "$tmp/state"
touch "$tmp/usr/bin/tg-ws-proxy"
printf 'PORT=1443\n' >"$tmp/etc/tg-ws-proxy/config.conf"
printf '%s\n' \
  '  sl  local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode' \
  >"$tmp/proc/net/tcp"
cp "$tmp/proc/net/tcp" "$tmp/proc/net/tcp6"

cat >"$tmp/uci" <<'EOF'
#!/bin/sh
set -eu

state="${MOCK_UCI_STATE:?}"
committed="$state.committed"
dirty="$state.dirty"
touch "$state"
[ -e "$committed" ] || cp "$state" "$committed"

[ "${1:-}" = -q ] && shift
command="${1:-}"
shift || true

resolve_section() {
  package="$1"
  selector="$2"
  case "$selector" in
    @*\[*\])
      type="${selector#@}"
      type="${type%%[*}"
      index="${selector#*[}"
      index="${index%]}"
      awk -v package="$package" -v type="$type" -v wanted="$index" '
        $1 == "section" && $2 == package && $4 == type {
          if (seen == wanted) { print $3; exit }
          seen++
        }
      ' "$state"
      ;;
    *) printf '%s\n' "$selector" ;;
  esac
}

get_value() {
  key="$1"
  package="${key%%.*}"
  rest="${key#*.}"
  selector="${rest%%.*}"
  section="$(resolve_section "$package" "$selector")"
  [ -n "$section" ] || return 1
  if [ "$rest" = "$selector" ]; then
    awk -v package="$package" -v section="$section" '
      $1 == "section" && $2 == package && $3 == section { print $4; found=1; exit }
      END { if (!found) exit 1 }
    ' "$state"
  else
    option="${rest#*.}"
    awk -v package="$package" -v section="$section" -v option="$option" '
      $1 == "option" && $2 == package && $3 == section && $4 == option {
        $1=$2=$3=$4=""
        sub(/^    /, "")
        print
        found=1
        exit
      }
      END { if (!found) exit 1 }
    ' "$state"
  fi
}

set_value() {
  assignment="$1"
  key="${assignment%%=*}"
  value="${assignment#*=}"
  package="${key%%.*}"
  rest="${key#*.}"
  selector="${rest%%.*}"
  section="$(resolve_section "$package" "$selector")"
  [ -n "$section" ] || section="$selector"
  output="$state.new"
  if [ "$rest" = "$selector" ]; then
    awk -v package="$package" -v section="$section" \
      '!( $1 == "section" && $2 == package && $3 == section )' "$state" >"$output"
    printf 'section %s %s %s\n' "$package" "$section" "$value" >>"$output"
  else
    option="${rest#*.}"
    awk -v package="$package" -v section="$section" -v option="$option" \
      '!( $1 == "option" && $2 == package && $3 == section && $4 == option )' \
      "$state" >"$output"
    printf 'option %s %s %s %s\n' "$package" "$section" "$option" "$value" >>"$output"
  fi
  mv "$output" "$state"
  touch "$dirty"
}

case "$command" in
  get) get_value "$1" ;;
  set) set_value "$1" ;;
  changes) [ -e "$dirty" ] && printf 'firewall.changed=true\n' || true ;;
  export) cat "$state" ;;
  commit)
    cp "$state" "$committed"
    rm -f "$dirty"
    ;;
  revert)
    cp "$committed" "$state"
    rm -f "$dirty"
    ;;
  import)
    cat >"$state"
    touch "$dirty"
    ;;
  *) exit 1 ;;
esac
EOF
chmod 755 "$tmp/uci"

cat >"$tmp/fw4" <<'EOF'
#!/bin/sh
case "${1:-}" in
  check) [ ! -e "${MOCK_FW4_FAIL_CHECK:?}" ] ;;
  reload) [ ! -e "${MOCK_FW4_FAIL_RELOAD:?}" ] ;;
  *) exit 2 ;;
esac
EOF
chmod 755 "$tmp/fw4"

uci_state="$tmp/firewall.state"
fail_check="$tmp/fail-check"
fail_reload="$tmp/fail-reload"
: >"$uci_state"
cp "$uci_state" "$uci_state.committed"

run_helper() {
  MTPROTO_MONITOR_ETC_ROOT="$tmp/etc" \
    MTPROTO_MONITOR_PROC_ROOT="$tmp/proc" \
    MTPROTO_MONITOR_USR_ROOT="$tmp/usr" \
    MTPROTO_MONITOR_STATE_DIR="$tmp/state" \
    MTPROTO_MONITOR_UCI="$tmp/uci" \
    MTPROTO_MONITOR_FW4="$tmp/fw4" \
    MOCK_UCI_STATE="$uci_state" \
    MOCK_FW4_FAIL_CHECK="$fail_check" \
    MOCK_FW4_FAIL_RELOAD="$fail_reload" \
    MTPROTO_MONITOR_LOCK_ATTEMPTS="${LOCK_ATTEMPTS:-10}" \
    MTPROTO_MONITOR_LOCK_WAIT=0 \
    "$root/runtime/mtproto-monitor.sh" "$@"
}

run_helper firewall-open 1443 | grep -q 'WAN access opened'
grep -q '^section firewall mtproto_monitor_1443 rule$' "$uci_state"
grep -q '^option firewall mtproto_monitor_1443 enabled 1$' "$uci_state" || true
run_helper firewall-close 1443 | grep -q 'WAN access closed'
grep -q '^option firewall mtproto_monitor_1443 enabled 0$' "$uci_state"
run_helper firewall-open 1443 | grep -q 'WAN access opened'
grep -q '^option firewall mtproto_monitor_1443 enabled 1$' "$uci_state"

before="$(sha256sum "$uci_state" | awk '{print $1}')"
if run_helper firewall-open 2443 >/dev/null 2>&1; then
  printf 'undetected port was accepted\n' >&2
  exit 1
fi
after="$(sha256sum "$uci_state" | awk '{print $1}')"
[ "$before" = "$after" ]

cat >"$uci_state" <<'EOF'
section firewall broad rule
option firewall broad src wan
option firewall broad proto tcp
option firewall broad dest_port 1000-2000
option firewall broad target ACCEPT
EOF
cp "$uci_state" "$uci_state.committed"
before="$(sha256sum "$uci_state" | awk '{print $1}')"
if run_helper firewall-close 1443 >"$tmp/broad.out" 2>&1; then
  printf 'shared ranged rule was modified\n' >&2
  exit 1
fi
grep -q 'refusing to modify it automatically' "$tmp/broad.out"
after="$(sha256sum "$uci_state" | awk '{print $1}')"
[ "$before" = "$after" ]

: >"$uci_state"
cp "$uci_state" "$uci_state.committed"
touch "$fail_check"
if run_helper firewall-open 1443 >/dev/null 2>&1; then
  printf 'failed fw4 check was accepted\n' >&2
  exit 1
fi
[ ! -s "$uci_state" ]
rm -f "$fail_check"

: >"$uci_state"
cp "$uci_state" "$uci_state.committed"
touch "$fail_reload"
if run_helper firewall-open 1443 >/dev/null 2>&1; then
  printf 'failed fw4 reload was accepted\n' >&2
  exit 1
fi
[ ! -s "$uci_state" ]
[ ! -s "$uci_state.committed" ]
rm -f "$fail_reload"

: >"$uci_state"
cp "$uci_state" "$uci_state.committed"
touch "$uci_state.dirty"
if run_helper firewall-open 1443 >"$tmp/pending.out" 2>&1; then
  printf 'pending firewall changes were ignored\n' >&2
  exit 1
fi
grep -q 'pending UCI changes' "$tmp/pending.out"
[ ! -s "$uci_state" ]
rm -f "$uci_state.dirty"

reset_state() {
  cat >"$uci_state"
  cp "$uci_state" "$uci_state.committed"
  rm -f "$uci_state.dirty"
}

# firewall4 widens a rule when a field is unset: an absent proto means "tcpudp"
# and an absent dest_port means every port. Both forms already reach the proxy
# port from WAN, so both must read as open.
reset_state <<'EOF'
section firewall implicit_proto rule
option firewall implicit_proto src wan
option firewall implicit_proto dest_port 1443
option firewall implicit_proto target ACCEPT
EOF
run_helper firewall-open 1443 | grep -q 'already open' || {
  printf 'a rule without proto was not recognised as open\n' >&2
  exit 1
}
run_helper firewall-status | grep -q '^port=1443 firewall=active'

reset_state <<'EOF'
section firewall implicit_ports rule
option firewall implicit_ports src wan
option firewall implicit_ports proto tcp
option firewall implicit_ports target ACCEPT
EOF
run_helper firewall-open 1443 | grep -q 'already open' || {
  printf 'a rule without dest_port was not recognised as open\n' >&2
  exit 1
}

# firewall4 parse_protocol maps each of these onto TCP.
for alias in tcp tcpudp all any 6 'tcp udp'; do
  reset_state <<EOF
section firewall alias_rule rule
option firewall alias_rule src wan
option firewall alias_rule proto $alias
option firewall alias_rule dest_port 1443
option firewall alias_rule target ACCEPT
EOF
  run_helper firewall-open 1443 | grep -q 'already open' || {
    printf 'proto %s was not recognised as covering TCP\n' "$alias" >&2
    exit 1
  }
done

# A UDP-only rule leaves the TCP port closed and must not read as open.
reset_state <<'EOF'
section firewall udp_only rule
option firewall udp_only src wan
option firewall udp_only proto udp
option firewall udp_only dest_port 1443
option firewall udp_only target ACCEPT
EOF
run_helper firewall-status | grep -q '^port=1443 firewall=missing' || {
  printf 'a UDP-only rule was reported as open TCP access\n' >&2
  exit 1
}

# A widened rule is reported, but closing it still refuses to edit a rule that
# is not an exact single-port TCP match.
reset_state <<'EOF'
section firewall implicit_proto rule
option firewall implicit_proto src wan
option firewall implicit_proto dest_port 1443
option firewall implicit_proto target ACCEPT
EOF
before="$(sha256sum "$uci_state" | awk '{print $1}')"
if run_helper firewall-close 1443 >"$tmp/implicit.out" 2>&1; then
  printf 'a rule without explicit proto was edited automatically\n' >&2
  exit 1
fi
grep -q 'refusing to modify it automatically' "$tmp/implicit.out"
[ "$before" = "$(sha256sum "$uci_state" | awk '{print $1}')" ]

# miniupnpd stops at the first perm_rule whose external range covers the port,
# so a deny behind a broader allow reserves nothing.
reset_state <<'EOF'
section upnpd allow_high perm_rule
option upnpd allow_high action allow
option upnpd allow_high ext_ports 1024-65535
section upnpd deny_mtproto perm_rule
option upnpd deny_mtproto action deny
option upnpd deny_mtproto ext_ports 1443
EOF
run_helper firewall-status | grep -q 'upnp=missing' || {
  printf 'a deny shadowed by an earlier allow was reported as reserved\n' >&2
  exit 1
}

reset_state <<'EOF'
section upnpd deny_mtproto perm_rule
option upnpd deny_mtproto action deny
option upnpd deny_mtproto ext_ports 1443
section upnpd allow_high perm_rule
option upnpd allow_high action allow
option upnpd allow_high ext_ports 1024-65535
EOF
run_helper firewall-status | grep -q 'upnp=active' || {
  printf 'an effective UPnP reservation was not reported\n' >&2
  exit 1
}

# A lock outlives a process killed before it could release it, and would
# otherwise refuse every later firewall action until /tmp was cleared by hand.
reset_state </dev/null
mkdir -p "$tmp/state/firewall.lock"
printf '999999\n' >"$tmp/state/firewall.lock/pid"
run_helper firewall-open 1443 | grep -q 'WAN access opened' || {
  printf 'a stale firewall lock was not reclaimed\n' >&2
  exit 1
}
[ ! -e "$tmp/state/firewall.lock" ] || {
  printf 'the firewall lock was not released\n' >&2
  exit 1
}

# A lock a live process holds is still honoured.
reset_state </dev/null
mkdir -p "$tmp/proc/4242" "$tmp/state/firewall.lock"
printf '4242\n' >"$tmp/state/firewall.lock/pid"
if LOCK_ATTEMPTS=2 run_helper firewall-open 1443 >"$tmp/held.out" 2>&1; then
  printf 'a lock held by a live process was ignored\n' >&2
  exit 1
fi
grep -q 'still running' "$tmp/held.out"
[ ! -s "$uci_state" ]
rm -rf "$tmp/state/firewall.lock" "$tmp/proc/4242"

# A reservation written as a range covers the port just as a single value does.
reset_state <<'EOF'
section upnpd deny_range perm_rule
option upnpd deny_range action deny
option upnpd deny_range ext_ports 1400-1500
EOF
run_helper firewall-status | grep -q 'upnp=active' || {
  printf 'a ranged UPnP reservation was not recognised\n' >&2
  exit 1
}

printf 'test-firewall OK\n'
