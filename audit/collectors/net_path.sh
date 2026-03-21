#!/usr/bin/env bash
# dev-cmd: alias=net_path name="Net Path" group=audit run=user legend=hide desc="Capture default route, DNS, and interfaces"

set -euo pipefail

OUTDIR="${1:-./current}"
OUTFILE="$OUTDIR/net_path.log"

mkdir -p "$OUTDIR"

{
  echo "=== DEFAULT ROUTE ==="
  route get default 2>&1 || echo "WARN: route get default failed (permissions restricted)"

  echo
  echo "=== DNS CONFIG ==="
  scutil --dns 2>&1 || echo "WARN: scutil --dns failed (permissions restricted)"

  echo
  echo "=== INTERFACES ==="
  ifconfig 2>&1 || echo "WARN: ifconfig failed (permissions restricted)"
} > "$OUTFILE"

echo "[net_path] route + dns captured"
