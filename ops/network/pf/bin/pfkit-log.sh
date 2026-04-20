#!/usr/bin/env bash
# dev-cmd: alias=pfkit.log name="pfkit log" group=net run=sudo legend=hide desc="Manage the pfkit block-log capture process and retained log files"
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
REPO_ROOT="$(cd "$ROOT_DIR/../../.." && pwd)"
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

legacy_state_dir() {
  printf '%s/Library/Logs/pfkit\n' "$(resolve_owner_home)"
}

state_dir() {
  printf '%s/pfkit\n' "${DEV_LOG_ROOT:-$REPO_ROOT/logs}"
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

legacy_pid_file() {
  printf '%s/blocks.pid\n' "$(legacy_state_dir)"
}

legacy_log_file() {
  printf '%s/blocks.log\n' "$(legacy_state_dir)"
}

legacy_stderr_file() {
  printf '%s/blocks.stderr.log\n' "$(legacy_state_dir)"
}

running_pid_from() {
  local pidfile="$1" pid
  [[ -f "$pidfile" ]] || return 1
  pid="$(<"$pidfile")"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  printf '%s\n' "$pid"
}

rotate_file() {
  local file="$1" max_bytes="$2" owner size
  [[ -f "$file" ]] || return 0
  size="$(stat -f '%z' "$file" 2>/dev/null || echo 0)"
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  (( size < max_bytes )) && return 0

  rm -f "$file.3"
  [[ -f "$file.2" ]] && mv "$file.2" "$file.3"
  [[ -f "$file.1" ]] && mv "$file.1" "$file.2"
  mv "$file" "$file.1"
  : > "$file"

  owner="$(resolve_owner)"
  chown "$owner":staff "$file" 2>/dev/null || true
}

ensure_state_dir() {
  local dir owner
  dir="$(state_dir)"
  owner="$(resolve_owner)"
  mkdir -p "$dir"
  chown "$owner":staff "$dir" 2>/dev/null || true

  if [[ ! -f "$(log_file)" && -f "$(legacy_log_file)" ]]; then
    cp "$(legacy_log_file)" "$(log_file)"
  fi
  if [[ ! -f "$(stderr_file)" && -f "$(legacy_stderr_file)" ]]; then
    cp "$(legacy_stderr_file)" "$(stderr_file)"
  fi

  touch "$(log_file)" "$(stderr_file)"
  rotate_file "$(log_file)" 5242880
  rotate_file "$(stderr_file)" 1048576
  chown "$owner":staff "$(log_file)" "$(stderr_file)" 2>/dev/null || true
}

log_notice() {
  ensure_state_dir
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$(log_file)"
}

running_pid() {
  running_pid_from "$(pid_file)" && return 0
  running_pid_from "$(legacy_pid_file)"
}

ensure_pflog_interface() {
  if ifconfig pflog0 >/dev/null 2>&1; then
    ifconfig pflog0 up >/dev/null 2>&1 || true
    return 0
  fi

  if ifconfig -C 2>/dev/null | tr ' ' '\n' | grep -qx 'pflog'; then
    ifconfig pflog0 create >/dev/null 2>&1 || true
    if ifconfig pflog0 >/dev/null 2>&1; then
      ifconfig pflog0 up >/dev/null 2>&1 || true
      return 0
    fi
  fi

  return 1
}

start_logger() {
  if running_pid_from "$(pid_file)" >/dev/null 2>&1; then
    echo ">> pfkit block logger already running (pid $(running_pid))"
    echo "   log: $(log_file)"
    return
  fi

  if running_pid_from "$(legacy_pid_file)" >/dev/null 2>&1; then
    local legacy_pid
    legacy_pid="$(running_pid_from "$(legacy_pid_file)")"
    echo ">> stopping legacy pfkit block logger (pid $legacy_pid)"
    kill "$legacy_pid" 2>/dev/null || true
    wait "$legacy_pid" 2>/dev/null || true
    rm -f "$(legacy_pid_file)"
  fi

  if ! ensure_pflog_interface; then
    log_notice "pfkit logger unavailable: pflog0 missing; block capture not started"
    echo ">> pfkit block logger unavailable (pflog0 missing)"
    echo "   log: $(log_file)"
    return
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
  if running_pid_from "$(pid_file)" >/dev/null 2>&1; then
    echo "  logger: running (pid $(running_pid_from "$(pid_file)"))"
  elif running_pid_from "$(legacy_pid_file)" >/dev/null 2>&1; then
    echo "  logger: running (legacy pid $(running_pid_from "$(legacy_pid_file)"))"
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
