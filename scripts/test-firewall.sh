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
    @rule\[*\])
      index="${selector#@rule[}"
      index="${index%]}"
      awk -v package="$package" -v wanted="$index" '
        $1 == "section" && $2 == package && $4 == "rule" {
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

printf 'test-firewall OK\n'
