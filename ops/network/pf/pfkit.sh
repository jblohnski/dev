#!/usr/bin/env bash
# dev-cmd: alias=pfup name=pfkit-update group=net run=sudo desc="update pfkit"
# Internal dispatcher for pfkit start, stop, update, and logs commands.
set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit: macos only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "run with sudo" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../../.." && pwd)"
ANCHOR_DST="/etc/pf.anchors/pfkit.anchor"

ensure_repo_files() {
  local anchor_template="$ROOT_DIR/pfkit.anchor"
  local env_file="$ROOT_DIR/pfkit.env"
  [[ -f "$anchor_template" ]] || { echo "pfkit: missing $anchor_template" >&2; exit 1; }
  [[ -f "$env_file" ]] || { echo "pfkit: missing $env_file" >&2; exit 1; }
}

usage() {
  cat <<'EOF'
usage: pfkit <command>

commands:
  start   update rules, enable pf, and start block logging
  stop    stop block logging, unload pfkit rules, and disable pf globally
  status  show whether pfkit is running
  update  repair wiring, render config, and load pfkit rules
  logs    manage or inspect retained block logs

logs:
  pfkit logs [report|tail|cat|path|clear|start|stop] [lines]

EOF
}

ensure_wired() {
  [[ -f /etc/pf.conf ]] || return 1
  grep -q '^load anchor "pfkit" from "/etc/pf\.anchors/pfkit\.anchor"' /etc/pf.conf &&
    grep -q '^anchor "pfkit"$' /etc/pf.conf
}

install_wiring() {
  local pfconf="/etc/pf.conf"
  local before after tmp
  mkdir -p /etc/pf.anchors
  [[ -f "$pfconf" && ! -f "$pfconf.pfkit.bak" ]] && cp "$pfconf" "$pfconf.pfkit.bak"
  [[ -f "$ANCHOR_DST" ]] || {
    printf '%s\n' '# pfkit placeholder; rendered rules are written by pfkit-apply.sh' > "$ANCHOR_DST"
    chmod 644 "$ANCHOR_DST"
    mark_update "$ANCHOR_DST"
  }

  before="$(cat "$pfconf" 2>/dev/null || true)"
  tmp="$(mktemp)"
  grep -vE '^# pfkit \(installed\)$|^anchor "pfkit"$|^anchor "pfkit/\*"$|^load anchor "pfkit" from "/etc/pf\.anchors/pfkit\.anchor"$' "$pfconf" > "$tmp"
  cat "$tmp" > "$pfconf"
  rm -f "$tmp"

  {
    echo
    echo "# pfkit (installed)"
    echo 'anchor "pfkit"'
    echo 'load anchor "pfkit" from "/etc/pf.anchors/pfkit.anchor"'
  } >> "$pfconf"

  after="$(cat "$pfconf" 2>/dev/null || true)"
  [[ "$before" == "$after" ]] || mark_update "$pfconf"

  run_quiet pfctl -q -nf "$pfconf"
  run_quiet pfctl -q -f "$pfconf"
  pfctl -q -e >/dev/null 2>&1 || true
}

use_color() {
  [[ -n "${FORCE_COLOR:-}" ]] || [[ -t 1 && -z "${NO_COLOR:-}" ]]
}

paint() {
  local code="$1" text="$2"
  if use_color; then
    printf '\033[%sm%s\033[0m' "$code" "$text"
  else
    printf '%s' "$text"
  fi
}

paint_state() {
  local value="$1"
  case "$value" in
    on|running|present|loaded|active)
      paint '1;32' "$value"
      ;;
    partial|stopped|missing)
      paint '1;33' "$value"
      ;;
    off|inactive|cleared)
      paint '1;31' "$value"
      ;;
    *)
      paint '2' "$value"
      ;;
  esac
}

state_color() {
  local value="$1"
  case "$value" in
    on|running|present|loaded|active)
      printf '1;32'
      ;;
    partial|stopped|missing)
      printf '1;33'
      ;;
    off|inactive|cleared)
      printf '1;31'
      ;;
    *)
      printf '2'
      ;;
  esac
}

row() {
  local key="$1" value="$2" extra="${3:-}"
  if [[ -n "$extra" ]]; then
    printf '  %s  %s  %s\n' "$(paint '1;36' "$(printf '%-5s' "$key")")" "$(paint "$(state_color "$value")" "$(printf '%-3s' "$value")")" "$extra"
  else
    printf '  %s  %s\n' "$(paint '1;36' "$(printf '%-5s' "$key")")" "$value"
  fi
}

print_recent_blocks() {
  local log_dir="$1"
  python3 - "$log_dir" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

log_dir = Path(sys.argv[1])
paths = [log_dir / "blocks.log", *(log_dir / f"blocks.log.{index}" for index in range(1, 4))]
events: list[tuple[str, str]] = []

for path in paths:
    if not path.is_file():
        continue
    try:
        lines = path.read_text(errors="ignore").splitlines()
    except OSError:
        continue
    for line in lines:
        match = re.match(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", line)
        if match:
            events.append((match.group(1), line.strip()))

for _, line in sorted(events, key=lambda item: item[0])[-5:]:
    print(line)
PY
}

run_quiet() {
  if ! "$@" >/dev/null 2>&1; then
    echo "pfkit: system pf command failed" >&2
    return 1
  fi
}

mark_update() {
  [[ -n "${PFKIT_UPDATE_REPORT:-}" ]] || return 0
  printf '%s\n' "$1" >> "$PFKIT_UPDATE_REPORT"
}

status_pfkit() {
  local status_line pfkit_rules logger_state logger_pid pf_state log_state summary_state log_dir
  status_line="$(pfctl -q -s info 2>/dev/null | sed -n '/^Status:/p' || true)"
  pfkit_rules="$(pfctl -q -a pfkit -sr 2>/dev/null || true)"
  pf_state="off"
  logger_state="stopped"
  logger_pid=""

  [[ "$status_line" == *"Enabled"* ]] && pf_state="on"

  log_dir="${DEV_LOG_ROOT:-$REPO_ROOT/logs}/pfkit"
  if [[ -f "$log_dir/blocks.pid" ]]; then
    logger_pid="$(cat "$log_dir/blocks.pid" 2>/dev/null || true)"
    if [[ -n "$logger_pid" ]] &&
      kill -0 "$logger_pid" 2>/dev/null &&
      [[ "$(ps -p "$logger_pid" -o command= 2>/dev/null || true)" == *"pfkit-log.sh run"* ]]; then
      logger_state="running"
    fi
  fi

  log_state="off"
  [[ "$logger_state" == "running" ]] && log_state="on"

  if [[ "$pf_state" == "on" && -n "$pfkit_rules" ]]; then
    summary_state="on"
  else
    summary_state="off"
  fi

  printf '%s  %s\n' "$(paint_state "$summary_state")" "pfkit"
  row pf "$pf_state"
  row log "$log_state" "$(paint '2' "$log_dir/blocks.log")"
  recent_blocks=()
  while IFS= read -r line; do
    recent_blocks+=("$line")
  done < <(print_recent_blocks "$log_dir")
  if (( ${#recent_blocks[@]} > 0 )); then
    row last "$(paint '2' "${#recent_blocks[@]}")"
    for line in "${recent_blocks[@]}"; do
      printf '  %s  %s\n' "$(paint '1;36' '     ')" "$(paint '2' "$line")"
    done
  fi
}

update_pfkit() {
  local quiet="${1:-}" report updated_files
  report="$(mktemp)"
  export PFKIT_UPDATE_REPORT="$report"
  ensure_repo_files
  if ! ensure_wired; then
    install_wiring
  fi
  PFKIT_QUIET=1 PFKIT_UPDATE_REPORT="$report" bash "$ROOT_DIR/pfkit-apply.sh"
  if [[ "$quiet" != "quiet" ]]; then
    updated_files="$(sort -u "$report" 2>/dev/null || true)"
    if [[ -n "$updated_files" ]]; then
      printf '%s  %s\n' "$(paint '1;32' updated)" "pfkit files"
      while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        row file "$file"
      done <<<"$updated_files"
    else
      printf '%s  %s\n' "$(paint '1;33' updated)" "no file changes"
    fi
  fi
  rm -f "$report"
}

start_pfkit() {
  update_pfkit quiet
  PFKIT_QUIET=1 bash "$ROOT_DIR/pfkit-log.sh" start
  status_pfkit
}

stop_pfkit() {
  PFKIT_QUIET=1 bash "$ROOT_DIR/pfkit-log.sh" stop

  if ensure_wired; then
    printf '%s\n' '# pfkit stopped' > "$ANCHOR_DST"
    chmod 644 "$ANCHOR_DST"
    run_quiet pfctl -q -a pfkit -nf "$ANCHOR_DST"
    run_quiet pfctl -q -a pfkit -f "$ANCHOR_DST"
  fi

  pfctl -d >/dev/null 2>&1 || true

  printf '%s  %s\n' "$(paint '1;31' stopped)" "pfkit stopped"
  row pf off
  row log off
}

logs_pfkit() {
  local log_cmd="${1:-report}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  case "$log_cmd" in
    report|tail|cat|path|clear|start|stop)
      bash "$ROOT_DIR/pfkit-log.sh" "$log_cmd" "$@"
      ;;
    *)
      bash "$ROOT_DIR/pfkit-log.sh" "$log_cmd" "$@"
      ;;
  esac
}

cmd="${1:-update}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  start)
    start_pfkit
    ;;
  status)
    status_pfkit
    ;;
  update)
    update_pfkit
    ;;
  logs)
    logs_pfkit "$@"
    ;;
  stop)
    stop_pfkit
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
