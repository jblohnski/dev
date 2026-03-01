#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:-./current}"
OUTFILE="$OUTDIR/net_live.log"

mkdir -p "$OUTDIR"

echo "[net_live] capturing socket snapshot..."

{
  echo "=== NETSTAT SNAPSHOT ==="
  date
  echo
  netstat -anv
  echo
  echo "=== ROUTING TABLE ==="
  netstat -rn
} > "$OUTFILE"

# summary only to stdout
EST=$(netstat -an | grep ESTABLISHED | wc -l | tr -d ' ')
echo "[net_live] established sockets: $EST"
