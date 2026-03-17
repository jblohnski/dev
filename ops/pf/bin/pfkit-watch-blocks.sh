#!/usr/bin/env bash
# @cmd: pfkit-watch-blocks
# @desc: Stream blocked packets from pflog0
# @tags: ops pf firewall monitor
# @run: sudo

set -euo pipefail

# Shows PF blocked packets if logging is enabled in base pf.conf.
# On many macOS installs, pflog is present but not heavily used.
# This will still help if you add "log" to rules.

exec sudo tcpdump -n -e -ttt -i pflog0
