#!/usr/bin/env bash
# dev-cmd: alias=launchctl name=Launchctl group=audit run=user legend=hide desc="Dump launchctl system and GUI trees"

set -euo pipefail

OUT="$1/launchctl_dump.txt"
{
  echo "==== launchctl print system ===="
  launchctl print system 2>/dev/null || true

  echo
  echo "==== launchctl print gui/$UID ===="
  launchctl print gui/$UID 2>/dev/null || true
} > "$OUT"
