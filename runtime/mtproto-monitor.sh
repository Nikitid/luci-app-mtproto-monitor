#!/bin/sh

set -eu

ETC_ROOT="${MTPROTO_MONITOR_ETC_ROOT:-/etc}"
PROC_ROOT="${MTPROTO_MONITOR_PROC_ROOT:-/proc}"
USR_ROOT="${MTPROTO_MONITOR_USR_ROOT:-/usr}"
STATE_DIR="${MTPROTO_MONITOR_STATE_DIR:-/tmp/mtproto-monitor}"
SAMPLE_INTERVAL="${MTPROTO_MONITOR_INTERVAL:-5}"
HISTORY_LIMIT="${MTPROTO_MONITOR_HISTORY_LIMIT:-360}"
UCI="${MTPROTO_MONITOR_UCI:-uci}"
FW4="${MTPROTO_MONITOR_FW4:-fw4}"

umask 077

instances() {
  cat <<'EOF'
go	TG WS Proxy Go	tg-ws-proxy	/usr/bin/tg-ws-proxy	1443	MTProto
go-legacy	TG WS Proxy Go (legacy)	tg-ws-proxy-go	/usr/bin/tg-ws-proxy-go	1080	SOCKS5
rust	TG WS Proxy Rust	tg-ws-proxy-rs	/usr/bin/tg-ws-proxy-rs	2443	MTProto
EOF
}

root_path() {
  case "$1" in
    /etc/*) printf '%s/%s\n' "$ETC_ROOT" "${1#/etc/}" ;;
    /usr/*) printf '%s/%s\n' "$USR_ROOT" "${1#/usr/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

is_number() {
  case "${1:-}" in
    '' | *[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

is_uint() {
  is_number "${1:-}" \
    && [ "$1" -ge 1 ] 2>/dev/null \
    && [ "$1" -le 65535 ] 2>/dev/null
}

process_pids() {
  expected="$(root_path "$1")"
  for process in "$PROC_ROOT"/[0-9]*; do
    [ -L "$process/exe" ] || continue
    [ "$(readlink "$process/exe" 2>/dev/null || true)" = "$expected" ] || continue
    printf '%s\n' "${process##*/}"
  done
}

port_from_cmdline() {
  pid="$1"
  [ -r "$PROC_ROOT/$pid/cmdline" ] || return 1
  tr '\000' '\n' <"$PROC_ROOT/$pid/cmdline" \
    | awk '
			previous == "--port" && /^[0-9]+$/ { print; exit }
			/^--port=[0-9]+$/ { sub(/^--port=/, ""); print; exit }
			{ previous = $0 }
		'
}

port_from_config() {
  file="$ETC_ROOT/tg-ws-proxy/config.conf"
  [ -r "$file" ] || return 1
  sed -n 's/^[[:space:]]*PORT[[:space:]]*=[[:space:]]*["'\'']\{0,1\}\([0-9][0-9]*\).*/\1/p' \
    "$file" | head -n 1
}

port_from_init() {
  service="$1"
  file="$ETC_ROOT/init.d/$service"
  [ -r "$file" ] || return 1
  sed -n \
    -e 's/.*--port[[:space:]]\{1,\}\([0-9][0-9]*\).*/\1/p' \
    -e 's/.*--port=\([0-9][0-9]*\).*/\1/p' \
    "$file" | head -n 1
}

detect_port() {
  service="$1"
  binary="$2"
  fallback="$3"
  port=""
  for pid in $(process_pids "$binary"); do
    port="$(port_from_cmdline "$pid" || true)"
    is_uint "$port" && break
    port=""
  done
  if [ -z "$port" ] && [ "$service" = tg-ws-proxy ]; then
    port="$(port_from_config || true)"
  fi
  if [ -z "$port" ]; then
    port="$(port_from_init "$service" || true)"
  fi
  is_uint "$port" || port="$fallback"
  printf '%s\n' "$port"
}

instance_installed() {
  service="$1"
  binary="$2"
  [ -e "$(root_path "$binary")" ] || [ -e "$ETC_ROOT/init.d/$service" ]
}

socket_inodes() {
  binary="$1"
  for pid in $(process_pids "$binary"); do
    for descriptor in "$PROC_ROOT/$pid"/fd/*; do
      [ -L "$descriptor" ] || continue
      readlink "$descriptor" 2>/dev/null || true
    done
  done | sed -n 's/^socket:\[\([0-9][0-9]*\)\]$/\1/p' | sort -u
}

socket_metrics_file() {
  port="$1"
  inodes="$2"
  output="$3"
  all_remotes="$4"
  : >"$output"
  [ -n "$inodes" ] || {
    printf 'connections=0\nclients=0\nlistening=0\n' >"$output"
    return
  }

  inode_file="$output.inodes"
  remote_file="$output.remotes"
  printf '%s\n' "$inodes" >"$inode_file"
  : >"$remote_file"
  port_hex="$(printf '%04X' "$port")"
  connections=0
  listening=0

  for table in "$PROC_ROOT/net/tcp" "$PROC_ROOT/net/tcp6"; do
    [ -r "$table" ] || continue
    result="$(awk -v wanted_port="$port_hex" -v remotes="$remote_file" \
      -v all_remotes="$all_remotes" '
			NR == FNR { owned[$1] = 1; next }
			FNR == 1 { next }
			{
				split($2, local, ":")
				if (!owned[$10] || toupper(local[2]) != wanted_port)
					next
				if ($4 == "0A")
					listening = 1
				else if ($4 == "01") {
					connections++
					split($3, remote, ":")
					print remote[1] >> remotes
					print remote[1] >> all_remotes
				}
			}
			END { print connections + 0, listening + 0 }
		' "$inode_file" "$table")"
    connections=$((connections + ${result%% *}))
    table_listening="${result##* }"
    [ "$table_listening" = 1 ] && listening=1
  done

  clients="$(sort -u "$remote_file" | sed '/^$/d' | wc -l | tr -d ' ')"
  printf 'connections=%s\nclients=%s\nlistening=%s\n' \
    "$connections" "$clients" "$listening" >"$output"
  rm -f "$inode_file" "$remote_file"
}

package_version() {
  service="$1"
  if command -v apk >/dev/null 2>&1; then
    apk list --installed "$service" 2>/dev/null \
      | sed -n "s/^${service}-\\([^ ]*\\).*/\\1/p" | head -n 1
  elif command -v opkg >/dev/null 2>&1; then
    opkg list-installed "$service" 2>/dev/null \
      | awk 'NR == 1 { print $3 }'
  fi
}

port_spec_contains() {
  wanted="$1"
  spec="$2"
  for token in $(printf '%s\n' "$spec" | tr ',' ' '); do
    case "$token" in
      "$wanted") return 0 ;;
      *-*)
        first="${token%%-*}"
        last="${token##*-}"
        if is_uint "$first" && is_uint "$last" \
          && [ "$wanted" -ge "$first" ] && [ "$wanted" -le "$last" ]; then
          return 0
        fi
        ;;
    esac
  done
  return 1
}

firewall_rule_matches() {
  index="$1"
  port="$2"
  include_disabled="${3:-0}"
  src="$("$UCI" -q get "firewall.@rule[$index].src" || true)"
  proto="$("$UCI" -q get "firewall.@rule[$index].proto" || true)"
  dest_port="$("$UCI" -q get "firewall.@rule[$index].dest_port" || true)"
  target="$("$UCI" -q get "firewall.@rule[$index].target" || true)"
  enabled="$("$UCI" -q get "firewall.@rule[$index].enabled" || echo 1)"
  [ "$src" = wan ] && [ "$target" = ACCEPT ] \
    && { [ "$include_disabled" = 1 ] || [ "$enabled" != 0 ]; } \
    && printf ' %s ' "$proto" | grep -q ' tcp ' \
    && port_spec_contains "$port" "$dest_port"
}

firewall_rule_exists() {
  port="$1"
  index=0
  while "$UCI" -q get "firewall.@rule[$index]" >/dev/null 2>&1; do
    firewall_rule_matches "$index" "$port" && return 0
    index=$((index + 1))
  done
  return 1
}

upnp_reserved() {
  port="$1"
  index=0
  while "$UCI" -q get "upnpd.@perm_rule[$index]" >/dev/null 2>&1; do
    action="$("$UCI" -q get "upnpd.@perm_rule[$index].action" || true)"
    ports="$("$UCI" -q get "upnpd.@perm_rule[$index].ext_ports" || true)"
    [ "$action" = deny ] && [ "$ports" = "$port" ] && return 0
    index=$((index + 1))
  done
  return 1
}

detected_ports() {
  instances | while IFS="$(printf '\t')" read -r key label service binary fallback protocol; do
    instance_installed "$service" "$binary" || continue
    detect_port "$service" "$binary" "$fallback"
  done | sort -nu
}

port_is_detected() {
  wanted="$1"
  is_uint "$wanted" || return 1
  for port in $(detected_ports); do
    [ "$port" = "$wanted" ] && return 0
  done
  return 1
}

sample_status() (
  mkdir -p "$STATE_DIR"
  tmp_dir="$STATE_DIR/status.$$"
  mkdir "$tmp_dir"
  trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

  active_connections=0
  installed=0
  running=0
  listening=0
  firewall_ready=1
  upnp_ready=1
  rows="$tmp_dir/instances"
  all_remotes="$tmp_dir/all-remotes"
  : >"$rows"
  : >"$all_remotes"

  instances | while IFS="$(printf '\t')" read -r key label service binary fallback protocol; do
    instance_installed "$service" "$binary" || continue
    port="$(detect_port "$service" "$binary" "$fallback")"
    pids="$(process_pids "$binary")"
    state=stopped
    [ -n "$pids" ] && state=running
    inodes="$(socket_inodes "$binary")"
    metrics="$tmp_dir/$key.metrics"
    socket_metrics_file "$port" "$inodes" "$metrics" "$all_remotes"
    clients="$(sed -n 's/^clients=//p' "$metrics")"
    connections="$(sed -n 's/^connections=//p' "$metrics")"
    is_listening="$(sed -n 's/^listening=//p' "$metrics")"
    version="$(package_version "$service" || true)"
    firewall=missing
    firewall_rule_exists "$port" && firewall=active
    reserved=not-applicable
    if "$UCI" -q get upnpd.config >/dev/null 2>&1; then
      reserved=missing
      upnp_reserved "$port" && reserved=active
    fi
    printf 'instance=%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$key" "$label" "$service" "${version:-unknown}" "$protocol" "$port" \
      "$state" "$is_listening" "$clients" "$connections" \
      "$firewall/$reserved" >>"$rows"
  done

  while IFS="$(printf '\t')" read -r prefix label service version protocol port state \
    is_listening clients connections protection; do
    [ -n "$prefix" ] || continue
    installed=$((installed + 1))
    [ "$state" = running ] && running=$((running + 1))
    [ "$is_listening" = 1 ] && listening=$((listening + 1))
    active_connections=$((active_connections + connections))
    case "$protection" in
      active/*) ;;
      *) firewall_ready=0 ;;
    esac
    case "$protection" in
      */missing) upnp_ready=0 ;;
    esac
  done <"$rows"
  total_clients="$(sort -u "$all_remotes" | sed '/^$/d' | wc -l | tr -d ' ')"

  [ "$installed" -gt 0 ] || {
    firewall_ready=0
    upnp_ready=0
  }

  printf 'timestamp=%s\n' "$(date +%s)"
  printf 'installed=%s\nrunning=%s\nlistening=%s\n' "$installed" "$running" "$listening"
  printf 'clients=%s\nconnections=%s\n' "$total_clients" "$active_connections"
  printf 'firewall=%s\n' "$([ "$firewall_ready" = 1 ] && echo active || echo missing)"
  printf 'upnp_reservation=%s\n' "$([ "$upnp_ready" = 1 ] && echo active || echo missing)"
  cat "$rows"
)

status() {
  latest="$STATE_DIR/latest"
  if [ -r "$latest" ]; then
    timestamp="$(sed -n 's/^timestamp=//p' "$latest" | head -n 1)"
    now="$(date +%s)"
    if is_number "$timestamp"; then
      age=$((now - timestamp))
      if [ "$age" -ge 0 ] && [ "$age" -le $((SAMPLE_INTERVAL * 3)) ]; then
        cat "$latest"
        return
      fi
    fi
  fi
  sample_status
}

append_history() {
  snapshot="$1"
  mkdir -p "$STATE_DIR"
  history="$STATE_DIR/history.tsv"
  tmp="$STATE_DIR/history.$$"
  timestamp="$(sed -n 's/^timestamp=//p' "$snapshot")"
  clients="$(sed -n 's/^clients=//p' "$snapshot")"
  connections="$(sed -n 's/^connections=//p' "$snapshot")"
  {
    [ -r "$history" ] && tail -n "$((HISTORY_LIMIT - 1))" "$history"
    printf '%s\t%s\t%s\n' "$timestamp" "$clients" "$connections"
  } >"$tmp"
  mv "$tmp" "$history"
}

collect() {
  mkdir -p "$STATE_DIR"
  while :; do
    snapshot="$STATE_DIR/snapshot.$$"
    if sample_status >"$snapshot"; then
      append_history "$snapshot"
      mv "$snapshot" "$STATE_DIR/latest"
    else
      rm -f "$snapshot"
    fi
    sleep "$SAMPLE_INTERVAL"
  done
}

history() {
  [ -r "$STATE_DIR/history.tsv" ] && cat "$STATE_DIR/history.tsv"
}

firewall_status() {
  found=0
  for port in $(detected_ports); do
    found=1
    printf 'port=%s firewall=%s upnp=%s\n' \
      "$port" \
      "$(firewall_rule_exists "$port" && echo active || echo missing)" \
      "$(upnp_reserved "$port" && echo active || echo missing)"
  done
  [ "$found" = 1 ] || printf 'port=none firewall=missing upnp=missing\n'
}

acquire_firewall_lock() {
  lock="$STATE_DIR/firewall.lock"
  mkdir -p "$STATE_DIR"
  attempts=0
  while ! mkdir "$lock" 2>/dev/null; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 10 ] || return 1
    sleep 1
  done
}

restore_firewall() {
  backup="$1"
  "$UCI" -q revert firewall || true
  "$UCI" -q import firewall <"$backup"
  "$UCI" commit firewall
}

apply_firewall_transaction() {
  backup="$1"
  if ! "$FW4" check >/dev/null 2>&1; then
    "$UCI" -q revert firewall || true
    printf 'firewall4 rejected the change; previous configuration kept.\n' >&2
    return 1
  fi
  if ! "$UCI" commit firewall; then
    "$UCI" -q revert firewall || true
    printf 'Unable to commit the firewall change.\n' >&2
    return 1
  fi
  if ! "$FW4" reload >/dev/null 2>&1; then
    restore_firewall "$backup"
    "$FW4" reload >/dev/null 2>&1 || true
    printf 'firewall4 reload failed; previous configuration restored.\n' >&2
    return 1
  fi
  rm -f "$STATE_DIR/latest"
}

firewall_open() (
  port="${1:-}"
  port_is_detected "$port" || {
    printf 'The port is not used by a detected proxy instance.\n' >&2
    exit 1
  }
  acquire_firewall_lock || {
    printf 'Another MTProto firewall action is still running.\n' >&2
    exit 1
  }
  backup="$(mktemp)"
  lock="$STATE_DIR/firewall.lock"
  trap 'rm -f "$backup"; rmdir "$lock" 2>/dev/null || true' EXIT HUP INT TERM
  [ -z "$("$UCI" changes firewall 2>/dev/null)" ] || {
    printf 'Firewall has pending UCI changes; apply or revert them first.\n' >&2
    exit 1
  }
  "$UCI" export firewall >"$backup"
  firewall_rule_exists "$port" && {
    printf 'WAN access is already open for TCP port %s.\n' "$port"
    exit 0
  }

  enabled_existing=0
  index=0
  while "$UCI" -q get "firewall.@rule[$index]" >/dev/null 2>&1; do
    if firewall_rule_matches "$index" "$port" 1; then
      proto="$("$UCI" -q get "firewall.@rule[$index].proto" || true)"
      dest_port="$("$UCI" -q get "firewall.@rule[$index].dest_port" || true)"
      enabled="$("$UCI" -q get "firewall.@rule[$index].enabled" || echo 1)"
      if [ "$proto" = tcp ] && [ "$dest_port" = "$port" ] && [ "$enabled" = 0 ]; then
        "$UCI" set "firewall.@rule[$index].enabled=1"
        enabled_existing=1
      fi
    fi
    index=$((index + 1))
  done

  if [ "$enabled_existing" = 0 ]; then
    section="mtproto_monitor_$port"
    if "$UCI" -q get "firewall.$section" >/dev/null 2>&1; then
      printf 'Firewall section %s already exists with incompatible settings.\n' "$section" >&2
      exit 1
    fi
    "$UCI" set "firewall.$section=rule"
    "$UCI" set "firewall.$section.name=Allow-MTProto-$port"
    "$UCI" set "firewall.$section.src=wan"
    "$UCI" set "firewall.$section.proto=tcp"
    "$UCI" set "firewall.$section.dest_port=$port"
    "$UCI" set "firewall.$section.target=ACCEPT"
  fi

  apply_firewall_transaction "$backup"
  printf 'WAN access opened for TCP port %s.\n' "$port"
)

firewall_close() (
  port="${1:-}"
  port_is_detected "$port" || {
    printf 'The port is not used by a detected proxy instance.\n' >&2
    exit 1
  }
  acquire_firewall_lock || {
    printf 'Another MTProto firewall action is still running.\n' >&2
    exit 1
  }
  backup="$(mktemp)"
  lock="$STATE_DIR/firewall.lock"
  trap 'rm -f "$backup"; rmdir "$lock" 2>/dev/null || true' EXIT HUP INT TERM
  [ -z "$("$UCI" changes firewall 2>/dev/null)" ] || {
    printf 'Firewall has pending UCI changes; apply or revert them first.\n' >&2
    exit 1
  }
  "$UCI" export firewall >"$backup"
  firewall_rule_exists "$port" || {
    printf 'WAN access is already closed for TCP port %s.\n' "$port"
    exit 0
  }

  index=0
  matches=0
  while "$UCI" -q get "firewall.@rule[$index]" >/dev/null 2>&1; do
    if firewall_rule_matches "$index" "$port"; then
      proto="$("$UCI" -q get "firewall.@rule[$index].proto" || true)"
      dest_port="$("$UCI" -q get "firewall.@rule[$index].dest_port" || true)"
      if [ "$proto" != tcp ] || [ "$dest_port" != "$port" ]; then
        printf 'TCP port %s is allowed by a shared or ranged firewall rule; refusing to modify it automatically.\n' \
          "$port" >&2
        exit 1
      fi
      matches=$((matches + 1))
    fi
    index=$((index + 1))
  done

  [ "$matches" -gt 0 ] || {
    printf 'No exact WAN rule was found for TCP port %s.\n' "$port" >&2
    exit 1
  }

  index=0
  while "$UCI" -q get "firewall.@rule[$index]" >/dev/null 2>&1; do
    if firewall_rule_matches "$index" "$port"; then
      "$UCI" set "firewall.@rule[$index].enabled=0"
    fi
    index=$((index + 1))
  done

  apply_firewall_transaction "$backup"
  printf 'WAN access closed for TCP port %s. Existing sessions may remain until they disconnect.\n' "$port"
)

usage() {
  printf 'Usage: %s {status|history|collect|firewall-status|firewall-open PORT|firewall-close PORT}\n' "$0" >&2
  exit 2
}

case "${1:-}" in
  status) status ;;
  history) history ;;
  collect) collect ;;
  firewall-status) firewall_status ;;
  firewall-open) firewall_open "${2:-}" ;;
  firewall-close) firewall_close "${2:-}" ;;
  *) usage ;;
esac
