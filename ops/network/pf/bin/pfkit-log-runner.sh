#!/usr/bin/env bash
# Background block-log capture for pfkit.

set -euo pipefail

if ! ifconfig pflog0 >/dev/null 2>&1; then
  echo "pfkit-log-runner: PF log interface does not exist: pflog0" >&2
  exit 1
fi

exec tcpdump -l -n -e -tttt -i pflog0 | awk '
  function flush_prev() {
    if (prev == "") {
      return
    }
    if (count > 1) {
      print prev " [x" count "]"
    } else {
      print prev
    }
    fflush()
  }

  {
    lower = tolower($0)
    if (lower !~ /(^|[[:space:]])block([[:space:]]|$)/) {
      next
    }

    if ($0 == prev) {
      count++
      next
    }

    flush_prev()
    prev = $0
    count = 1
  }

  END {
    flush_prev()
  }
'
