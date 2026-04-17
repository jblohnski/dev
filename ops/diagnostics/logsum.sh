#!/usr/bin/env bash
# dev-cmd: alias=logsum name=logsum group=audit run=user legend=hide desc="Summarize macOS unified logs for hangs/beachballs (system + Firefox)"

set -euo pipefail

command -v log >/dev/null 2>&1 || { echo "macOS 'log' tool not found." >&2; exit 1; }

# Usage:
#   ./logsum.sh
#   ./logsum.sh 30m
#   ./logsum.sh --last 2h --top 5
#   ./logsum.sh --counts --top 10

LAST_RANGE="30m"
TOP_N=3
SHOW_COUNTS=0

usage() {
  cat <<'EOF'
Usage: ./logsum.sh [range] [--last RANGE] [--top N] [--counts] [--help]

Summarize recent macOS unified logs for hangs, beachballs, and Firefox/network-adjacent issues.

Options:
  range         Shorthand positional range, for example 30m or 2h
  --last RANGE  Explicit time window passed to log show
  --top N       Show the latest N matching entries per section (default: 3)
  --counts      Include aggregate counts alongside the recent entries
  --help        Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --last)
      [[ $# -ge 2 ]] || { echo "error: --last requires a value" >&2; exit 1; }
      LAST_RANGE="$2"
      shift 2
      ;;
    --top|-n)
      [[ $# -ge 2 ]] || { echo "error: --top requires a value" >&2; exit 1; }
      [[ "$2" =~ ^[0-9]+$ && "$2" -gt 0 ]] || { echo "error: --top expects a positive integer" >&2; exit 1; }
      TOP_N="$2"
      shift 2
      ;;
    --counts)
      SHOW_COUNTS=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      LAST_RANGE="$1"
      shift
      ;;
  esac
done

RANGE=(--last "$LAST_RANGE")

SECTIONS=(
  'FAULT (system-wide)|logType == "fault"'
  'ERROR (system-wide)|logType == "error"'
  'Firefox faults|process == "firefox" AND logType == "fault"'
  'Firefox errors|process == "firefox" AND logType == "error"'
  'Network stack errors|(process == "kernel" OR process == "mDNSResponder" OR process == "neagent" OR process == "nesessionmanager") AND (logType == "error" OR logType == "fault")'
)

collect_logs() {
  local predicate="$1"
  local outfile="$2"

  log show "${RANGE[@]}" \
    --info --debug \
    --predicate "$predicate" \
    --style syslog 2>/dev/null \
    | awk '$0 !~ /^Timestamp[[:space:]]+\(process\)\[PID\][[:space:]]*$/ && $0 != ""' > "$outfile"
}

print_section() {
  local label="$1"
  local predicate="$2"
  local tmp
  local match_count

  tmp="$(mktemp -t logsum.section.XXXXXX)"
  collect_logs "$predicate" "$tmp"
  match_count="$(wc -l < "$tmp" | tr -d ' ')"

  printf "== %s ==\n" "$label"
  if [[ "$SHOW_COUNTS" -eq 1 ]]; then
    printf "count: %s\n" "$match_count"
  fi

  if [[ "$match_count" -eq 0 ]]; then
    echo "no matching entries"
    echo
    rm -f "$tmp"
    return
  fi

  if [[ "$TOP_N" -eq 1 ]]; then
    printf "latest %s entry:\n" "$TOP_N"
  else
    printf "latest %s entries:\n" "$TOP_N"
  fi
  tail -n "$TOP_N" "$tmp" | sed 's/^/  /'
  echo
  rm -f "$tmp"
}

echo "==== macOS Hang / Beachball Diagnostic Summary ===="
echo "Range: ${RANGE[*]}"
echo "Recent entries per section: $TOP_N"
if [[ "$SHOW_COUNTS" -eq 1 ]]; then
  echo "Aggregate counts: enabled"
fi
echo

for section in "${SECTIONS[@]}"; do
  IFS='|' read -r label predicate <<< "$section"
  print_section "$label" "$predicate"
done
