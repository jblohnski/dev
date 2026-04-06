#!/usr/bin/env bash
# dev-cmd: alias=pfr name="PF Remove" group=net run=sudo legend=hide desc="Internal PF uninstall helper"

set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit-uninstall: macOS only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

PFCONF="/etc/pf.conf"
ANCHOR_DST="/etc/pf.anchors/pfkit.anchor"

# Restore pf.conf if we have a backup from install
if [[ -f "$PFCONF.pfkit.bak" ]]; then
  cp "$PFCONF.pfkit.bak" "$PFCONF"
  echo ">> Restored $PFCONF from $PFCONF.pfkit.bak"
else
  echo ">> No $PFCONF.pfkit.bak found; removing pfkit lines only"
  tmp=$(mktemp)
  # Remove our two lines and comment header if present
  grep -vE '^# pfkit \(installed\)$|^anchor "pfkit"$|^anchor "pfkit/\*"$|^load anchor "pfkit" from "/etc/pf\.anchors/pfkit\.anchor"$' "$PFCONF" > "$tmp"
  cp "$tmp" "$PFCONF"
  rm -f "$tmp"
fi

rm -f "$ANCHOR_DST"

pfctl -f /etc/pf.conf

echo ">> Uninstalled pfkit"
