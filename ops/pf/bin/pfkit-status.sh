#!/usr/bin/env bash
# dev-cmd: alias=pfs name="PF Status" group=sys run=sudo desc="Show live PF and pfkit status"

set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit-status: macOS only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

PFCONF="/etc/pf.conf"
ANCHOR_DST="/etc/pf.anchors/pfkit.anchor"

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

LOG_DIR="$(resolve_owner_home)/Library/Logs/pfkit"
LOG_FILE="$LOG_DIR/blocks.log"
LOG_ERR="$LOG_DIR/blocks.stderr.log"
LOG_PID="$LOG_DIR/blocks.pid"

status_line="$(pfctl -q -s info | sed -n '/^Status:/p')"
main_anchors="$(pfctl -q -sr | grep 'anchor ' || true)"
nat_anchors="$(pfctl -q -sn || true)"
pfkit_rules="$(pfctl -q -a pfkit -sr || true)"
pfkit_labels="$(pfctl -q -s labels 2>/dev/null | grep 'pfkit:' || true)"
utun_ifaces="$(ifconfig -l | tr ' ' '\n' | awk '/^utun[0-9]+$/')"

pfconf_state="missing"
if [[ -f "$PFCONF" ]]; then
  if grep -q '^anchor "pfkit/\*"' "$PFCONF" && grep -q '^load anchor "pfkit" from "/etc/pf.anchors/pfkit.anchor"' "$PFCONF"; then
    pfconf_state="wired"
  else
    pfconf_state="present, no pfkit wiring"
  fi
fi

anchor_file_state="missing"
[[ -f "$ANCHOR_DST" ]] && anchor_file_state="present"

echo "PF"
echo "  ${status_line:-Status: unknown}"
echo "  pf.conf: $pfconf_state"
echo "  anchor file: $anchor_file_state"
echo
echo "Anchors"
if [[ -n "$main_anchors" ]]; then
  printf '%s\n' "$main_anchors"
else
  echo "(none)"
fi
echo
echo "Interfaces"
if [[ -n "$utun_ifaces" ]]; then
  echo "utun detected:"
  printf '%s\n' "$utun_ifaces"
else
  echo "utun detected: none"
fi
echo
echo "Translation Rules"
if [[ -n "$nat_anchors" ]]; then
  printf '%s\n' "$nat_anchors"
else
  echo "(none)"
fi
echo
echo "pfkit Rules"
if [[ -n "$pfkit_rules" ]]; then
  printf '%s\n' "$pfkit_rules"
else
  echo "(pfkit anchor has no active rules)"
fi
echo
echo "pfkit Label Counters"
if [[ -n "$pfkit_labels" ]]; then
  printf '%s\n' "$pfkit_labels"
else
  echo "(no pfkit label counters)"
fi
echo
echo "PF Log Capture"
if [[ -f "$LOG_PID" ]] && kill -0 "$(cat "$LOG_PID")" 2>/dev/null; then
  echo "  logger: running (pid $(cat "$LOG_PID"))"
else
  echo "  logger: stopped"
fi
echo "  log file: $LOG_FILE"
echo "  err file: $LOG_ERR"
