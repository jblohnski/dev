#!/usr/bin/env bash
# dev-cmd: alias=pf.logrun name="PF Log Runner" group=sys run=sudo legend=hide desc="Internal pfkit block-log capture runner"
# Background block-log capture for pfkit.

set -euo pipefail

if ! ifconfig pflog0 >/dev/null 2>&1; then
  echo "pfkit-log-runner: PF log interface does not exist: pflog0" >&2
  exit 1
fi

exec tcpdump -l -n -e -tttt -i pflog0 | awk '
  {
    line = tolower($0)
    if (line ~ /(^|[[:space:]])block([[:space:]]|$)/) {
      print
      fflush()
    }
  }
'
