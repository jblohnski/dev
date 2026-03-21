#!/usr/bin/env bash
# dev-cmd: alias=processes name=Processes group=audit run=user legend=hide desc="Capture sorted process list snapshot"

set -euo pipefail

OUT="$1/processes.txt"

if ! ps -axo pid,ppid,user,comm 2>/dev/null | sort > "$OUT"; then
  {
    echo "WARN: unable to read full process list (permissions restricted)"
    date
  } > "$OUT"
fi
