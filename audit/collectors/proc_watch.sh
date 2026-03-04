#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:-./current}"
OUTFILE="$OUTDIR/proc_watch.log"

mkdir -p "$OUTDIR"

echo "[proc_watch] sampling short-lived processes (5s window)..."

{
  echo "=== PROCESS BURST SAMPLE ==="
  date
  echo
} > "$OUTFILE"

# sample repeatedly to catch ephemeral processes
for i in {1..10}; do
  ps -axo pid,ppid,user,uid,command >> "$OUTFILE" 2>/dev/null || {
    echo "WARN: ps sample failed (permissions restricted)" >> "$OUTFILE"
    break
  }
  sleep 0.5
done

# extract anything non-Apple running as root
grep -v "com.apple" "$OUTFILE" | grep " 0 " >> "$OUTFILE.root_only" || true

ROOT_COUNT=$(wc -l < "$OUTFILE.root_only" || echo 0)

echo "[proc_watch] root non-Apple entries: $ROOT_COUNT"
