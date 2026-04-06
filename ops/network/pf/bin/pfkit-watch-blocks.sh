#!/usr/bin/env bash
# dev-cmd: alias=pfb name="PF Blocks" group=net run=sudo legend=hide desc="Internal PF block watch helper"

set -euo pipefail

# Shows PF blocked packets on pflog0.

if ! ifconfig pflog0 >/dev/null 2>&1 && ifconfig -C 2>/dev/null | tr ' ' '\n' | grep -qx 'pflog'; then
  ifconfig pflog0 create >/dev/null 2>&1 || true
  ifconfig pflog0 up >/dev/null 2>&1 || true
fi

if ! ifconfig pflog0 >/dev/null 2>&1; then
  echo "PF log interface does not exist: pflog0" >&2
  exit 1
fi

sudo tcpdump -l -n -e -ttt -i pflog0 | awk '
  {
    line = tolower($0)
    if (line ~ /(^|[[:space:]])block([[:space:]]|$)/) {
      print
      fflush()
    }
  }
'
