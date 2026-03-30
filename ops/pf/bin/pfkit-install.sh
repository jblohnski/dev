#!/usr/bin/env bash
# dev-cmd: alias=pfi name="PF Install" group=sys run=sudo desc="Install pfkit anchor and pf.conf wiring"

set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit-install: macOS only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANCHOR_SRC="$ROOT_DIR/anchors/pfkit.anchor"
ANCHOR_DST="/etc/pf.anchors/pfkit.anchor"
PFCONF="/etc/pf.conf"

mkdir -p /etc/pf.anchors

# Backup once per install
[[ -f "$PFCONF" && ! -f "$PFCONF.pfkit.bak" ]] && cp "$PFCONF" "$PFCONF.pfkit.bak"

cp "$ANCHOR_SRC" "$ANCHOR_DST"
chmod 644 "$ANCHOR_DST"

need_lines=0

grep -qE '^anchor\s+"pfkit/\*"' "$PFCONF" || need_lines=1
if [[ $need_lines -eq 1 ]]; then
  {
    echo
    echo "# pfkit (installed)"
    echo 'anchor "pfkit/*"'
    echo 'load anchor "pfkit" from "/etc/pf.anchors/pfkit.anchor"'
  } >> "$PFCONF"
fi

echo ">> Installed anchor at $ANCHOR_DST"
echo ">> pf.conf backed up at: $PFCONF.pfkit.bak (if it did not already exist)"
