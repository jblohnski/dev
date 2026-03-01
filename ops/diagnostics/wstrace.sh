#!/usr/bin/env bash
# @desc: Trace WindowServer-related faults/errors for UI stutter and beachballs
# @tags: diag logs ui macos
# @run: user

set -euo pipefail

command -v log >/dev/null 2>&1 || { echo "macOS 'log' tool not found." >&2; exit 1; }

# Usage:
#   ./wstrace.sh 15m
#   ./wstrace.sh 2h

RANGE=(--last "${1:-30m}")

count() {
  local label="$1"
  local predicate="$2"

  printf "%-34s %8d\n" "$label:" \
    "$(log show "${RANGE[@]}" \
      --info --debug \
      --predicate "$predicate" \
      --style syslog 2>/dev/null | wc -l | tr -d ' ')"
}

echo "==== WindowServer Root-Cause Trace ===="
echo "Range: ${RANGE[*]}"
echo

# ------------------------------------------------------------------
# 1. High-level WindowServer health
# ------------------------------------------------------------------
count "WindowServer faults" \
  'process == "WindowServer" AND logType == "fault"'

count "WindowServer errors" \
  'process == "WindowServer" AND logType == "error"'

count "WindowServer total log entries" \
  'process == "WindowServer"'

echo
# ------------------------------------------------------------------
# 2. Supporting subsystems that often correlate with UI glitches
# ------------------------------------------------------------------
count "CoreGraphics faults/errors" \
  '(subsystem BEGINSWITH "com.apple.CoreGraphics") AND (logType == "fault" OR logType == "error")'

count "HID faults/errors" \
  '(subsystem CONTAINS "HID") AND (logType == "fault" OR logType == "error")'
