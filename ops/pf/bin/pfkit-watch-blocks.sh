#!/usr/bin/env bash
# dev-cmd: alias=pfb name="PF Blocks" group=sys run=sudo desc="Stream blocked PF log lines from pflog0"

set -euo pipefail

# Shows PF blocked packets on pflog0.

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
