#!/usr/bin/env bash
# dev-cmd: alias=persistence name=Persistence group=audit run=user legend=hide desc="Collect persistence surfaces and login items"

set -euo pipefail

OUT="$1/persistence.txt"

{
  echo "==== /Library LaunchDaemons ===="
  ls -al /Library/LaunchDaemons 2>/dev/null || true

  echo
  echo "==== /Library LaunchAgents ===="
  ls -al /Library/LaunchAgents 2>/dev/null || true

  echo
  echo "==== USER LaunchAgents ===="
  ls -al "$HOME/Library/LaunchAgents" 2>/dev/null || true

  echo
  echo "==== Login Items ===="
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || true

  echo
  echo "==== Background Items ===="
  system_profiler SPLoginItemDataType 2>/dev/null || true

  echo
  echo "==== Cron (user) ===="
  crontab -l 2>/dev/null || true

  echo
  echo "==== Cron (system) ===="
  ls -al /etc/cron* 2>/dev/null || true

  echo
  echo "==== At jobs ===="
  atq 2>/dev/null || true

  echo
  echo "==== Profiles / MDM ===="
  profiles status -type enrollment 2>/dev/null || true
  profiles list 2>/dev/null || true

} > "$OUT"
