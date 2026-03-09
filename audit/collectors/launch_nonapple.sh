#!/usr/bin/env bash
# @desc: Collect non-Apple launch agents and daemons
# @tags: audit collector launch persistence
# @run: user

set -euo pipefail

OUTDIR="${1:-./current}"
OUTFILE="$OUTDIR/launch_nonapple.log"

mkdir -p "$OUTDIR"

echo "[launch] scanning non-Apple launch agents..."

{
  echo "=== USER LAUNCH AGENTS ==="
  ls ~/Library/LaunchAgents 2>/dev/null || true

  echo
  echo "=== SYSTEM LAUNCH AGENTS ==="
  ls /Library/LaunchAgents 2>/dev/null || true

  echo
  echo "=== SYSTEM LAUNCH DAEMONS ==="
  ls /Library/LaunchDaemons 2>/dev/null || true
} > "$OUTFILE"

COUNT=$(wc -l < "$OUTFILE" | tr -d ' ')
echo "[launch] entries logged"
