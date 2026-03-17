#!/usr/bin/env bash
# @cmd: pfkit-watch-dns
# @desc: Stream DNS packets from selected interface
# @tags: ops pf dns monitor
# @run: sudo

set -euo pipefail

IF="${1:-en0}"

exec sudo tcpdump -l -n -i "$IF" '(udp port 53 or tcp port 53 or udp port 5353)'
