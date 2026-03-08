#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYZER="$ROOT_DIR/analysis/zeek_snapshot.py"
OUT_DIR="$ROOT_DIR/report/zeek"

usage() {
  cat <<USAGE
Usage:
  ./zeek-audit.sh [log_dir] [run_id] [-- analyzer args]

Examples:
  ./zeek-audit.sh
  ./zeek-audit.sh ./zlogs run01
  ./zeek-audit.sh ./zlogs run01 -- --uid CtvOlP1Ej5cQULCyA5 --window-seconds 180
  ./zeek-audit.sh ./zlogs run02 -- --src-ip 192.168.1.157 --dst-ip 75.102.5.99 --dst-port 443 --ts 2026-03-06T20:45:25Z

Analyzer passthrough examples:
  --uid <zeek_uid>
  --ip <host_ip>
  --src-ip <ip> --dst-ip <ip> [--dst-port <port>] [--ts <epoch|iso>]
  --window-seconds <n>
  --time-tolerance-seconds <n>
  --enrich-ipinfo
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

LOG_DIR="${1:-$ROOT_DIR/zlogs}"
RUN_ID="${2:-$(date +%Y%m%d-%H%M%S)}"

EXTRA=()
if [[ "${3:-}" == "--" ]]; then
  shift 3
  EXTRA=("$@")
elif [[ $# -gt 2 ]]; then
  echo "error: extra analyzer args must follow '--'" >&2
  usage >&2
  exit 2
fi

if [[ ! -d "$LOG_DIR" || ! -f "$LOG_DIR/conn.log" ]]; then
  FALLBACK="$ROOT_DIR/../zlogs"
  if [[ -d "$FALLBACK" && -f "$FALLBACK/conn.log" ]]; then
    LOG_DIR="$FALLBACK"
  fi
fi

if [[ ! -d "$LOG_DIR" || ! -f "$LOG_DIR/conn.log" ]]; then
  echo "error: conn.log not found in '$LOG_DIR' (or fallback ../zlogs)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

OUT_JSON="$OUT_DIR/zeek-$RUN_ID.json"
OUT_BULLETS="$OUT_DIR/zeek-$RUN_ID.summary.txt"
OUT_DOT="$OUT_DIR/zeek-$RUN_ID.graph.dot"
OUT_MD="$OUT_DIR/zeek-$RUN_ID.md"

python3 "$ANALYZER" \
  --log-dir "$LOG_DIR" \
  --out-json "$OUT_JSON" \
  --out-bullets "$OUT_BULLETS" \
  --out-dot "$OUT_DOT" \
  --out-md "$OUT_MD" \
  "${EXTRA[@]}"

echo "Zeek report JSON: $OUT_JSON"
echo "Zeek summary:     $OUT_BULLETS"
echo "Zeek markdown:    $OUT_MD"
echo "Zeek graph DOT:   $OUT_DOT"
if command -v dot >/dev/null 2>&1; then
  PNG="${OUT_DOT%.dot}.png"
  dot -Tpng "$OUT_DOT" -o "$PNG" || true
  [[ -f "$PNG" ]] && echo "Zeek graph PNG:   $PNG"
fi
