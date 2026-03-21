#!/usr/bin/env bash
# dev-cmd: alias=pfkit-watch-dns name=pfkit-watch-dns group=net run=sudo desc="Stream DNS packets from selected interface"

set -euo pipefail

IF="${1:-en0}"

exec sudo tcpdump -l -n -i "$IF" '(udp port 53 or tcp port 53 or udp port 5353)'
