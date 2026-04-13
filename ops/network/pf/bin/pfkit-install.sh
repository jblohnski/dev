#!/usr/bin/env bash
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
ANCHOR_DST="/etc/pf.anchors/pfkit.anchor"
PFCONF="/etc/pf.conf"
CANONICAL_ANCHOR_LINE='anchor "pfkit"'
CANONICAL_LOAD_LINE='load anchor "pfkit" from "/etc/pf.anchors/pfkit.anchor"'

mkdir -p /etc/pf.anchors

# Backup once per install
[[ -f "$PFCONF" && ! -f "$PFCONF.pfkit.bak" ]] && cp "$PFCONF" "$PFCONF.pfkit.bak"

printf '%s\n' '# pfkit placeholder; rendered rules are written by pfkit-apply.sh' > "$ANCHOR_DST"
chmod 644 "$ANCHOR_DST"

pfconf_before="$(cat "$PFCONF" 2>/dev/null || true)"
tmp="$(mktemp)"
grep -vE '^# pfkit \(installed\)$|^anchor "pfkit"$|^anchor "pfkit/\*"$|^load anchor "pfkit" from "/etc/pf\.anchors/pfkit\.anchor"$' "$PFCONF" > "$tmp"
cat "$tmp" > "$PFCONF"
rm -f "$tmp"

if ! grep -q '^anchor "pfkit"$' "$PFCONF" || ! grep -q '^load anchor "pfkit" from "/etc/pf\.anchors/pfkit\.anchor"$' "$PFCONF"; then
  {
    echo
    echo "# pfkit (installed)"
    echo "$CANONICAL_ANCHOR_LINE"
    echo "$CANONICAL_LOAD_LINE"
  } >> "$PFCONF"
fi

pfconf_after="$(cat "$PFCONF" 2>/dev/null || true)"
if [[ "$pfconf_before" != "$pfconf_after" ]]; then
  pfctl -nf "$PFCONF"
  pfctl -f "$PFCONF"
  pfctl -e 2>/dev/null || true
fi

echo ">> Installed anchor at $ANCHOR_DST"
echo ">> pf.conf backed up at: $PFCONF.pfkit.bak (if it did not already exist)"
