#!/usr/bin/env bash
# @desc: Capture live socket and route snapshot
# @tags: audit collector network live
# @run: user

set -euo pipefail

OUTDIR="${1:-./current}"
OUTFILE="$OUTDIR/net_live.log"

mkdir -p "$OUTDIR"

echo "[net_live] capturing socket snapshot..."

{
  echo "=== NETSTAT SNAPSHOT ==="
  date
  echo
  netstat -anv 2>&1 || echo "WARN: netstat -anv failed (permissions restricted)"
  echo
  echo "=== ROUTING TABLE ==="
  netstat -rn 2>&1 || echo "WARN: netstat -rn failed (permissions restricted)"
} > "$OUTFILE"

# summary only to stdout
EST="$(netstat -an 2>/dev/null | grep ESTABLISHED | wc -l | tr -d ' ' || echo 0)"
echo "[net_live] established sockets: $EST"
