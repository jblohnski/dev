#!/usr/bin/env bash
# Internal dispatcher for pfkit start, stop, update, and logs commands.
set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit: macos only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "run with sudo" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../../.." && pwd)"
ANCHOR_DST="/etc/pf.anchors/pfkit.anchor"

ensure_repo_files() {
  local anchor_template="$ROOT_DIR/pfkit.anchor"
  local env_file="$ROOT_DIR/pfkit.env"
  [[ -f "$anchor_template" ]] || { echo "pfkit: missing $anchor_template" >&2; exit 1; }
  [[ -f "$env_file" ]] || { echo "pfkit: missing $env_file" >&2; exit 1; }
}

usage() {
  cat <<'EOF'
usage: pfkit <command>

commands:
  start   update rules, enable pf, and start block logging
  stop    stop block logging, unload pfkit rules, and disable pf globally
  status  show whether pfkit is running
  update  repair wiring, render config, and load pfkit rules
  logs    manage or inspect retained block logs

logs:
  pfkit logs [report|tail|cat|path|clear|start|stop] [lines]

EOF
}

ensure_wired() {
  [[ -f /etc/pf.conf ]] || return 1
  grep -q '^load anchor "pfkit" from "/etc/pf\.anchors/pfkit\.anchor"' /etc/pf.conf &&
    grep -q '^anchor "pfkit"$' /etc/pf.conf
}

install_wiring() {
  local pfconf="/etc/pf.conf"
  local tmp
  mkdir -p /etc/pf.anchors
  [[ -f "$pfconf" && ! -f "$pfconf.pfkit.bak" ]] && cp "$pfconf" "$pfconf.pfkit.bak"
  [[ -f "$ANCHOR_DST" ]] || {
    printf '%s\n' '# pfkit placeholder; rendered rules are written by pfkit-apply.sh' > "$ANCHOR_DST"
    chmod 644 "$ANCHOR_DST"
  }

  tmp="$(mktemp)"
  grep -vE '^# pfkit \(installed\)$|^anchor "pfkit"$|^anchor "pfkit/\*"$|^load anchor "pfkit" from "/etc/pf\.anchors/pfkit\.anchor"$' "$pfconf" > "$tmp"
  cat "$tmp" > "$pfconf"
  rm -f "$tmp"

  {
    echo
    echo "# pfkit (installed)"
    echo 'anchor "pfkit"'
    echo 'load anchor "pfkit" from "/etc/pf.anchors/pfkit.anchor"'
  } >> "$pfconf"

  pfctl -q -nf "$pfconf" >/dev/null
  pfctl -q -f "$pfconf" >/dev/null
  pfctl -q -e >/dev/null 2>&1 || true
}

use_color() {
  [[ -n "${FORCE_COLOR:-}" ]] || [[ -t 1 && -z "${NO_COLOR:-}" ]]
}

paint() {
  local code="$1" text="$2"
  if use_color; then
    printf '\033[%sm%s\033[0m' "$code" "$text"
  else
    printf '%s' "$text"
  fi
}

paint_state() {
  local value="$1"
  case "$value" in
    on|running|present|loaded|active)
      paint '1;32' "$value"
      ;;
    partial|stopped|missing)
      paint '1;33' "$value"
      ;;
    off|inactive|cleared)
      paint '1;31' "$value"
      ;;
    *)
      paint '2' "$value"
      ;;
  esac
}

status_pfkit() {
  local status_line pfkit_rules logger_state logger_pid pf_state pfkit_state pflog_state overall
  status_line="$(pfctl -q -s info 2>/dev/null | sed -n '/^Status:/p' || true)"
  pfkit_rules="$(pfctl -q -a pfkit -sr 2>/dev/null || true)"
  pf_state="off"
  pfkit_state="off"
  pflog_state="missing"
  logger_state="stopped"
  logger_pid=""

  [[ "$status_line" == *"Enabled"* ]] && pf_state="on"
  [[ -n "$pfkit_rules" ]] && pfkit_state="on"
  if ifconfig pflog0 >/dev/null 2>&1; then
    pflog_state="present"
  fi

  local log_dir="${DEV_LOG_ROOT:-$REPO_ROOT/logs}/pfkit"
  if [[ -f "$log_dir/blocks.pid" ]]; then
    logger_pid="$(cat "$log_dir/blocks.pid" 2>/dev/null || true)"
    if [[ -n "$logger_pid" ]] &&
      kill -0 "$logger_pid" 2>/dev/null &&
      [[ "$(ps -p "$logger_pid" -o command= 2>/dev/null || true)" == *"pfkit-log.sh run"* ]]; then
      logger_state="running"
    fi
  fi

  overall="stopped"
  if [[ "$pf_state" == "on" && "$pfkit_state" == "on" && "$logger_state" == "running" ]]; then
    overall="running"
  elif [[ "$pf_state" == "on" && "$pfkit_state" == "on" ]]; then
    overall="partial"
  fi
  if [[ "$overall" == "running" ]]; then
    printf '%s  %s\n' "$(paint '1;32' running)" "pfkit active"
  elif [[ "$overall" == "partial" ]]; then
    printf '%s  %s\n' "$(paint '1;33' partial)" "pfkit rules loaded; logger stopped"
  else
    printf '%s  %s\n' "$(paint '1;31' stopped)" "pfkit inactive"
  fi

  printf '  pf      : %s\n' "$(paint_state "$pf_state")"
  printf '  anchor  : %s\n' "$(paint_state "$pfkit_state")"
  printf '  logger  : %s%s\n' "$(paint_state "$logger_state")" "${logger_pid:+ pid=$logger_pid}"
  printf '  pflog0  : %s\n' "$(paint_state "$pflog_state")"
  printf '  log     : %s\n' "$(paint '2' "$log_dir/blocks.log")"
}

update_pfkit() {
  local quiet="${1:-}"
  ensure_repo_files
  if ! ensure_wired; then
    install_wiring
  fi
  PFKIT_QUIET=1 bash "$ROOT_DIR/pfkit-apply.sh"
  if [[ "$quiet" != "quiet" ]]; then
    printf '%s  %s\n' "$(paint '1;32' updated)" "pfkit rules loaded"
    status_pfkit
  fi
}

start_pfkit() {
  update_pfkit quiet
  bash "$ROOT_DIR/pfkit-log.sh" start
  status_pfkit
}

stop_pfkit() {
  bash "$ROOT_DIR/pfkit-log.sh" stop

  if ensure_wired; then
    printf '%s\n' '# pfkit stopped' > "$ANCHOR_DST"
    chmod 644 "$ANCHOR_DST"
    pfctl -q -a pfkit -nf "$ANCHOR_DST" >/dev/null
    pfctl -q -a pfkit -f "$ANCHOR_DST" >/dev/null
  fi

  pfctl -d >/dev/null 2>&1 || true

  printf '%s  %s\n' "$(paint '1;31' stopped)" "pfkit stopped"
  printf '  pf      : off\n'
  printf '  anchor  : cleared\n'
  printf '  logger  : stopped\n'
}

logs_pfkit() {
  local log_cmd="${1:-report}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  case "$log_cmd" in
    report|tail|cat|path|clear|start|stop)
      bash "$ROOT_DIR/pfkit-log.sh" "$log_cmd" "$@"
      ;;
    *)
      bash "$ROOT_DIR/pfkit-log.sh" "$log_cmd" "$@"
      ;;
  esac
}

cmd="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  start)
    start_pfkit
    ;;
  status)
    status_pfkit
    ;;
  update)
    update_pfkit
    ;;
  logs)
    logs_pfkit "$@"
    ;;
  stop)
    stop_pfkit
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
