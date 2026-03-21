#!/usr/bin/env bash
# dev-cmd: alias=logsum name=logsum group=audit run=user desc="Summarize macOS unified logs for hangs/beachballs (system + Firefox)"

set -euo pipefail

command -v log >/dev/null 2>&1 || { echo "macOS 'log' tool not found." >&2; exit 1; }

# Usage:
#   ./logsum.sh 30m
#   ./logsum.sh 2h

RANGE=(--last "${1:-30m}")

logcount() {
  local label="$1"
  local predicate="$2"

  printf "%-28s %8d\n" "$label:" \
    "$(log show "${RANGE[@]}" \
      --info --debug \
      --predicate "$predicate" \
      --style syslog 2>/dev/null | wc -l | tr -d ' ')"
}

echo "==== macOS Hang / Beachball Diagnostic Summary ===="
echo "Range: ${RANGE[*]}"
echo

# --- Global severity ---
logcount "FAULT (system-wide)"   'logType == "fault"'
logcount "ERROR (system-wide)"   'logType == "error"'

echo
# --- Firefox isolation ---
logcount "Firefox faults" \
  'process == "firefox" AND logType == "fault"'

logcount "Firefox errors" \
  'process == "firefox" AND logType == "error"'

echo
# --- Network-ish hints often correlated with stutter/hangs ---
logcount "Network stack errors" \
  '(process == "kernel" OR process == "mDNSResponder" OR process == "neagent" OR process == "nesessionmanager") AND (logType == "error" OR logType == "fault")'
