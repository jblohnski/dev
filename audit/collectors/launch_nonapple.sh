#!/usr/bin/env bash
# dev-cmd: alias=launch_nonapple name="Launch Nonapple" group=audit run=user legend=hide desc="Collect non-Apple launch agents and daemons"

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
