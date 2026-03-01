#!/usr/bin/env bash
set -euo pipefail

OUT="$1/extensions.txt"

kextstat 2>/dev/null > "$OUT" || true
systemextensionsctl list 2>/dev/null >> "$OUT" || true
