#!/usr/bin/env bash
# dev-cmd: alias=network name=Network group=audit run=user legend=hide desc="Capture active network connections via lsof"

set -euo pipefail

OUT="$1/network.txt"
lsof -i -n -P 2>/dev/null > "$OUT" || true
