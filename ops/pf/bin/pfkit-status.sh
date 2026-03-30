#!/usr/bin/env bash
# dev-cmd: alias=pfs name="PF Status" group=sys run=sudo desc="Show live PF and pfkit status"

set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit-status: macOS only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

PFCONF="/etc/pf.conf"
ANCHOR_DST="/etc/pf.anchors/pfkit.anchor"

status_line="$(pfctl -q -s info | sed -n '/^Status:/p')"
main_anchors="$(pfctl -q -sr | grep 'anchor ' || true)"
nat_anchors="$(pfctl -q -sn || true)"
pfkit_rules="$(pfctl -q -a pfkit -sr || true)"
utun_ifaces="$(ifconfig -l | tr ' ' '\n' | awk '/^utun[0-9]+$/')"

pfconf_state="missing"
if [[ -f "$PFCONF" ]]; then
  if grep -q '^anchor "pfkit/\*"' "$PFCONF" && grep -q '^load anchor "pfkit" from "/etc/pf.anchors/pfkit.anchor"' "$PFCONF"; then
    pfconf_state="wired"
  else
    pfconf_state="present, no pfkit wiring"
  fi
fi

anchor_file_state="missing"
[[ -f "$ANCHOR_DST" ]] && anchor_file_state="present"

echo "PF"
echo "  ${status_line:-Status: unknown}"
echo "  pf.conf: $pfconf_state"
echo "  anchor file: $anchor_file_state"
echo
echo "Anchors"
if [[ -n "$main_anchors" ]]; then
  printf '%s\n' "$main_anchors"
else
  echo "(none)"
fi
echo
echo "Interfaces"
if [[ -n "$utun_ifaces" ]]; then
  echo "utun detected:"
  printf '%s\n' "$utun_ifaces"
else
  echo "utun detected: none"
fi
echo
echo "Translation Rules"
if [[ -n "$nat_anchors" ]]; then
  printf '%s\n' "$nat_anchors"
else
  echo "(none)"
fi
echo
echo "pfkit Rules"
if [[ -n "$pfkit_rules" ]]; then
  printf '%s\n' "$pfkit_rules"
else
  echo "(pfkit anchor has no active rules)"
fi
