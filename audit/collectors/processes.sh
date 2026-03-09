#!/usr/bin/env bash
# @desc: Capture sorted process list snapshot
# @tags: audit collector process snapshot
# @run: user

set -euo pipefail

OUT="$1/processes.txt"

if ! ps -axo pid,ppid,user,comm 2>/dev/null | sort > "$OUT"; then
  {
    echo "WARN: unable to read full process list (permissions restricted)"
    date
  } > "$OUT"
fi
