#!/usr/bin/env bash
set -euo pipefail

OUT="$1/network.txt"
lsof -i -n -P 2>/dev/null > "$OUT" || true
