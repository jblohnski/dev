#!/usr/bin/env bash
set -euo pipefail

# Shows PF blocked packets if logging is enabled in base pf.conf.
# On many macOS installs, pflog is present but not heavily used.
# This will still help if you add "log" to rules.

exec sudo tcpdump -n -e -ttt -i pflog0
