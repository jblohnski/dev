#!/usr/bin/env bash
set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit-status: macOS only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../../.." && pwd)"

resolve_owner() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
    return
  fi
  id -un
}

resolve_owner_home() {
  local owner home
  owner="$(resolve_owner)"
  home="$(dscl . -read "/Users/$owner" NFSHomeDirectory 2>/dev/null | awk 'NR==1{print $2}')"
  if [[ -z "$home" ]]; then
    home="${HOME:-/var/root}"
  fi
  printf '%s\n' "$home"
}

LOG_DIR="${DEV_LOG_ROOT:-$REPO_ROOT/logs}/pfkit"
LEGACY_LOG_DIR="$(resolve_owner_home)/Library/Logs/pfkit"
LOG_FILE="$LOG_DIR/blocks.log"
LOG_PID="$LOG_DIR/blocks.pid"
LEGACY_LOG_PID="$LEGACY_LOG_DIR/blocks.pid"
LOG_LINES="${PFKIT_STATUS_LOG_LINES:-20}"

status_line="$(pfctl -q -s info | sed -n '/^Status:/p')"
pfkit_rules="$(pfctl -q -a pfkit -sr || true)"

pf_status="off"
if [[ "$status_line" == *"Enabled"* ]]; then
  pf_status="on"
fi

pfkit_status="off"
if [[ -n "$pfkit_rules" ]]; then
  pfkit_status="on"
fi

logger_status="stopped"
if [[ -f "$LOG_PID" ]] && kill -0 "$(cat "$LOG_PID")" 2>/dev/null; then
  logger_status="running"
elif [[ -f "$LEGACY_LOG_PID" ]] && kill -0 "$(cat "$LEGACY_LOG_PID")" 2>/dev/null; then
  logger_status="running (legacy)"
elif ! ifconfig pflog0 >/dev/null 2>&1; then
  logger_status="unavailable (pflog0 missing)"
fi

overall_status="off"
if [[ "$pf_status" == "on" && "$pfkit_status" == "on" ]]; then
  overall_status="on"
fi

echo "PF"
echo "  status: $overall_status"
echo "  pf: $pf_status"
echo "  logger: $logger_status"
echo "  log file: $LOG_FILE"
echo
echo "Log Output"
if [[ ! -f "$LOG_FILE" ]]; then
  echo "(missing)"
elif [[ ! -s "$LOG_FILE" ]]; then
  echo "(empty)"
else
  tail -n "$LOG_LINES" "$LOG_FILE"
fi
