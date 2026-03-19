#!/usr/bin/env bash
# @desc: Collect kernel/system extension listings
# @tags: audit collector extensions
# @run: user

set -euo pipefail

OUT="$1/extensions.txt"

kextstat 2>/dev/null > "$OUT" || true
systemextensionsctl list 2>/dev/null >> "$OUT" || true
