#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:-./current}"
OUTFILE="$OUTDIR/net_path.log"

mkdir -p "$OUTDIR"

{
  echo "=== DEFAULT ROUTE ==="
  route get default

  echo
  echo "=== DNS CONFIG ==="
  scutil --dns

  echo
  echo "=== INTERFACES ==="
  ifconfig
} > "$OUTFILE"

echo "[net_path] route + dns captured"
