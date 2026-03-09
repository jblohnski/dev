#!/usr/bin/env bash
# @desc: Capture active network connections via lsof
# @tags: audit collector network lsof
# @run: user

set -euo pipefail

OUT="$1/network.txt"
lsof -i -n -P 2>/dev/null > "$OUT" || true
