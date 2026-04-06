#!/usr/bin/env bash
# dev-cmd: alias=pf.logctl name="PF Log Helper" group=sys run=sudo legend=hide desc="Internal pfkit block-log lifecycle helper"
# Helper for pfkit log capture lifecycle. Intended to be driven by pfkit.sh.

set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit-log: macOS only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/bin/pfkit-log-runner.sh"

resolve_owner() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
    return
  fi
  id -un
}

resolve_owner_home() {
  local owner
  owner="$(resolve_owner)"
  local home=""
  home="$(dscl . -read "/Users/$owner" NFSHomeDirectory 2>/dev/null | awk 'NR==1{print $2}')"
  if [[ -z "$home" ]]; then
    home="${HOME:-/var/root}"
  fi
  printf '%s\n' "$home"
}

state_dir() {
  printf '%s/Library/Logs/pfkit\n' "$(resolve_owner_home)"
}

pid_file() {
  printf '%s/blocks.pid\n' "$(state_dir)"
}

log_file() {
  printf '%s/blocks.log\n' "$(state_dir)"
}

stderr_file() {
  printf '%s/blocks.stderr.log\n' "$(state_dir)"
}

ensure_state_dir() {
  local dir owner
  dir="$(state_dir)"
  owner="$(resolve_owner)"
  mkdir -p "$dir"
  touch "$(log_file)" "$(stderr_file)"
  chown "$owner":staff "$dir" "$(log_file)" "$(stderr_file)" 2>/dev/null || true
}

running_pid() {
  local pidfile pid
  pidfile="$(pid_file)"
  [[ -f "$pidfile" ]] || return 1
  pid="$(<"$pidfile")"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  printf '%s\n' "$pid"
}

start_logger() {
  if running_pid >/dev/null 2>&1; then
    echo ">> pfkit block logger already running (pid $(running_pid))"
    echo "   log: $(log_file)"
    return
  fi

  if ! ifconfig pflog0 >/dev/null 2>&1; then
    echo "pfkit-log: PF log interface does not exist: pflog0" >&2
    exit 1
  fi

  ensure_state_dir
  nohup "$RUNNER" >>"$(log_file)" 2>>"$(stderr_file)" </dev/null &
  echo "$!" > "$(pid_file)"
  sleep 1
  if running_pid >/dev/null 2>&1; then
    echo ">> pfkit block logger started"
    echo "   pid : $(running_pid)"
    echo "   log : $(log_file)"
    echo "   err : $(stderr_file)"
    return
  fi

  echo "pfkit-log: failed to start block logger" >&2
  exit 1
}

stop_logger() {
  local pidfile pid
  pidfile="$(pid_file)"
  if ! pid="$(running_pid)"; then
    rm -f "$pidfile"
    echo ">> pfkit block logger is not running"
    return
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -f "$pidfile"
  echo ">> pfkit block logger stopped"
}

status_logger() {
  ensure_state_dir
  echo "PF Log Capture"
  if running_pid >/dev/null 2>&1; then
    echo "  logger: running (pid $(running_pid))"
  else
    echo "  logger: stopped"
  fi
  echo "  log file: $(log_file)"
  echo "  err file: $(stderr_file)"
}

tail_logger() {
  ensure_state_dir
  tail -n "${1:-50}" "$(log_file)"
}

cat_logger() {
  ensure_state_dir
  cat "$(log_file)"
}

clear_logger() {
  ensure_state_dir
  : > "$(log_file)"
  : > "$(stderr_file)"
  echo ">> cleared $(log_file)"
}

usage() {
  cat <<'EOF'
usage: pfkit-log.sh [start|stop|status|tail|cat|path|clear] [lines]
EOF
}

cmd="${1:-status}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  start)
    start_logger
    ;;
  stop)
    stop_logger
    ;;
  status)
    status_logger
    ;;
  tail)
    tail_logger "${1:-50}"
    ;;
  cat)
    cat_logger
    ;;
  path)
    ensure_state_dir
    log_file
    ;;
  clear)
    clear_logger
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
