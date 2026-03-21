#!/usr/bin/env bash
# dev-cmd: alias=extensions name=Extensions group=audit run=user legend=hide desc="Collect kernel/system extension listings"

set -euo pipefail

OUT="$1/extensions.txt"

kextstat 2>/dev/null > "$OUT" || true
systemextensionsctl list 2>/dev/null >> "$OUT" || true
