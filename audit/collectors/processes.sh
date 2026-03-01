#!/usr/bin/env bash
set -euo pipefail

OUT="$1/processes.txt"

ps -axo pid,ppid,user,comm | sort > "$OUT"
