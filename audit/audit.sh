#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASELINE_DIR="$ROOT_DIR/baseline"
CURRENT_DIR="$ROOT_DIR/current"
REPORT_DIR="$ROOT_DIR/report"
ARCHIVE_DIR="$ROOT_DIR/archives"
COLLECTORS_DIR="$ROOT_DIR/collectors"
SCRIPTS_DIR="$ROOT_DIR/scripts"

RUN_TS="$(date +"%Y%m%d_%H%M%S")"

usage() {
  cat <<EOF
Usage:
  ./audit.sh --baseline            Create/refresh baseline snapshot (archives previous baseline)
  ./audit.sh                       Create current snapshot + analysis + baseline diff (archives previous current/report)
  ./audit.sh --reset | --clear     Remove ALL generated data (baseline/current/report/archives)
  ./audit.sh --verbose             Show collector stdout in addition to the run summary

Notes:
  - Snapshots are written atomically via temp dirs, then swapped into place.
  - Previous baseline/current/report are moved to: archives/<name>_<timestamp>/
  - Full collector logs for a run are stored under: report/collectors/
EOF
}

log() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

reset_all() {
  log "[audit] resetting all generated state..."
  rm -rf "$BASELINE_DIR" "$CURRENT_DIR" "$REPORT_DIR" "$ARCHIVE_DIR"
  log "[audit] reset complete"
  exit 0
}

archive_if_exists() {
  local d="$1"
  local name="$2"
  if [[ -d "$d" ]]; then
    mkdir -p "$ARCHIVE_DIR"
    local dest="$ARCHIVE_DIR/${name}_${RUN_TS}"
    mv "$d" "$dest"
    log "[audit] archived $name -> $(basename "$dest")"
  fi
}

run_collectors() {
  local target_dir="$1"
  local collector_log_dir="$2"
  local verbose="${3:-0}"

  mkdir -p "$target_dir" "$collector_log_dir"

  # Stable ordering (explicit)
  local collectors=(
    "trust.sh"
    "processes.sh"
    "proc_watch.sh"
    "network.sh"
    "net_live.sh"
    "net_path.sh"
    "persistence.sh"
    "launch_nonapple.sh"
    "launchctl.sh"
    "extensions.sh"
    "signing.sh"
    "binaries.sh"
  )

  log "[audit] collectors:"
  local c
  for c in "${collectors[@]}"; do
    local path="$COLLECTORS_DIR/$c"
    if [[ ! -f "$path" ]]; then
      warn "[audit] missing collector: $c\n"
      continue
    fi

    local logf="$collector_log_dir/${c%.sh}.log"
    local start_ns end_ns dur_ms rc lastline
    start_ns="$(python3 - <<'PY'
import time; print(time.time_ns())
PY
)"
    set +e
    bash "$path" "$target_dir" >"$logf" 2>&1
    rc=$?
    set -e
    end_ns="$(python3 - <<'PY'
import time; print(time.time_ns())
PY
)"
    dur_ms="$(( (end_ns - start_ns) / 1000000 ))"
    lastline="$(tail -n 1 "$logf" 2>/dev/null || true)"

    if [[ "$rc" -eq 0 ]]; then
      log "  - ${c%.sh}: OK (${dur_ms}ms) ${lastline}"
    else
      log "  - ${c%.sh}: FAIL (${dur_ms}ms) (see collectors/${c%.sh}.log)"
      if [[ "$verbose" -eq 1 ]]; then
        log "----- ${c%.sh} output -----"
        sed -n '1,200p' "$logf" || true
        log "---------------------------"
      fi
    fi

    if [[ "$verbose" -eq 1 && "$rc" -eq 0 ]]; then
      # show only the last few lines for signal
      sed -n '1,40p' "$logf" | sed 's/^/      /' || true
    fi
  done
}

print_exec_summary() {
  local summary_md="$1"
  if [[ ! -f "$summary_md" ]]; then
    return 0
  fi
  log ""
  log "=== Executive summary ==="
  # Print only the "Executive summary" section header + bullets, stop at next header
  awk '
    BEGIN{p=0}
    /^## Executive summary/{p=1; print; next}
    p==1 && /^## /{exit}
    p==1{print}
  ' "$summary_md"
  log "========================="
}

make_baseline() {
  log "[audit] creating baseline snapshot..."
  archive_if_exists "$BASELINE_DIR" "baseline"

  local tmp="$ROOT_DIR/.baseline_tmp_${RUN_TS}"
  rm -rf "$tmp"
  mkdir -p "$tmp"

  local collector_logs="$tmp/.collector_logs"
  run_collectors "$tmp" "$collector_logs" "${AUDIT_VERBOSE:-0}"

  date > "$tmp/BASELINE_CREATED_AT.txt"

  mv "$tmp" "$BASELINE_DIR"
  log "[audit] baseline complete -> $BASELINE_DIR"
}

make_current_and_report() {
  if [[ ! -d "$BASELINE_DIR" ]]; then
    warn "[audit] no baseline present. run: ./audit.sh --baseline\n"
    exit 1
  fi

  archive_if_exists "$CURRENT_DIR" "current"
  archive_if_exists "$REPORT_DIR" "report"

  local tmp_current="$ROOT_DIR/.current_tmp_${RUN_TS}"
  local tmp_report="$ROOT_DIR/.report_tmp_${RUN_TS}"
  rm -rf "$tmp_current" "$tmp_report"
  mkdir -p "$tmp_current" "$tmp_report"

  log "[audit] creating current snapshot..."
  local collector_logs="$tmp_report/collectors"
  run_collectors "$tmp_current" "$collector_logs" "${AUDIT_VERBOSE:-0}"

  # Keep raw diff for forensics (noisy by design)
  diff -ru "$BASELINE_DIR" "$tmp_current" > "$tmp_report/diff_raw.txt" || true

  # Normalized diff + metrics + summary
  if [[ -x "$SCRIPTS_DIR/analyze_run.py" ]]; then
    python3 "$SCRIPTS_DIR/analyze_run.py" --current "$tmp_current" --baseline "$BASELINE_DIR" --report "$tmp_report"
  else
    warn "[audit] missing analyzer: scripts/analyze_run.py\n"
  fi

  mv "$tmp_current" "$CURRENT_DIR"
  mv "$tmp_report" "$REPORT_DIR"

  log "[audit] report written to:"
  log "  - $REPORT_DIR/summary.md"
  log "  - $REPORT_DIR/summary.json"
  log "  - $REPORT_DIR/diff_normalized.txt"
  log "  - $REPORT_DIR/diff_raw.txt"
  log "  - $REPORT_DIR/collectors/"

  print_exec_summary "$REPORT_DIR/summary.md"
}

# ---- arg handling ----

AUDIT_VERBOSE=0

case "${1:-}" in
  --baseline)
    make_baseline
    ;;
  --verbose)
    AUDIT_VERBOSE=1
    make_current_and_report
    ;;
  --reset|--clear)
    reset_all
    ;;
  "" )
    make_current_and_report
    ;;
  *)
    usage
    exit 1
    ;;
esac
