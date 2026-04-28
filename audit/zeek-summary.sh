#!/usr/bin/env bash
# dev-cmd: alias=zs name=zs group=audit run=user legend=hide desc="Summarize raw Zeek logs with a quick overview or optional lnav queries"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_LOG_DIR="${ZEEK_LOG_DIR:-${DEV_LOG_ROOT:-$ROOT_DIR/../logs}/zeek}"
MODE="summary"
TOP_N=10
LOG_DIR=""

usage() {
  cat <<'EOF'
Usage:
  ./zeek-summary.sh [--top N] [log_dir]
  ./zeek-summary.sh --lnav [--top N] [log_dir]

Modes:
  default   quick raw Zeek overview from conn/dns/ssl/weird logs
  --lnav    run lnav-backed SQL summaries against the Zeek log set

Examples:
  ./zeek-summary.sh
  ./zeek-summary.sh --top 15
  ./zeek-summary.sh --lnav
  ./zeek-summary.sh --lnav --top 20 ../logs/zeek
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lnav)
      MODE="lnav"
      shift
      ;;
    --top|-n)
      [[ $# -ge 2 ]] || { echo "error: --top requires a value" >&2; exit 1; }
      [[ "$2" =~ ^[0-9]+$ && "$2" -gt 0 ]] || { echo "error: --top expects a positive integer" >&2; exit 1; }
      TOP_N="$2"
      shift 2
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
      [[ -z "$LOG_DIR" ]] || { echo "error: unexpected extra argument: $1" >&2; exit 1; }
      LOG_DIR="$1"
      shift
      ;;
  esac
done

resolve_log_dir() {
  local candidate="${LOG_DIR:-$DEFAULT_LOG_DIR}"
  if [[ -d "$candidate" && -f "$candidate/conn.log" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  for fallback in "$ROOT_DIR/../logs/zeek" "$ROOT_DIR/zlogs" "$ROOT_DIR/../zlogs" "$ROOT_DIR" "$HOME/zlogs"; do
    if [[ -d "$fallback" && -f "$fallback/conn.log" ]]; then
      printf '%s\n' "$fallback"
      return 0
    fi
  done

  return 1
}

LOG_DIR="$(resolve_log_dir)" || {
  echo "error: conn.log not found in configured or fallback Zeek log roots" >&2
  exit 1
}

if [[ "$MODE" == "lnav" ]]; then
  command -v lnav >/dev/null 2>&1 || {
    echo "error: lnav is not installed or not in PATH" >&2
    exit 1
  }

  shopt -s nullglob
  LOG_FILES=("$LOG_DIR"/*.log)
  shopt -u nullglob
  [[ ${#LOG_FILES[@]} -gt 0 ]] || {
    echo "error: no .log files found in $LOG_DIR" >&2
    exit 1
  }

  run_query() {
    local title="$1"
    local query="$2"
    printf '\n=== %s ===\n' "$title"
    lnav -n "${LOG_FILES[@]}" -c ";$query" -c ':quit'
  }

  run_query "Timespan + Total Connections" \
    'SELECT MIN(log_time) AS start, MAX(log_time) AS end, COUNT(*) AS total_conn_rows FROM bro_conn_log;'

  run_query "Connections per Hour" \
    'SELECT strftime("%Y-%m-%d %H:00", log_time) AS hour, COUNT(*) AS conns FROM bro_conn_log GROUP BY hour ORDER BY hour;'

  run_query "Top Services" \
    "SELECT bro_service, COUNT(*) AS c FROM bro_conn_log GROUP BY bro_service ORDER BY c DESC LIMIT $TOP_N;"

  run_query "Top Source Hosts" \
    "SELECT bro_id_orig_h AS src, COUNT(*) AS c FROM bro_conn_log GROUP BY src ORDER BY c DESC LIMIT $TOP_N;"

  run_query "Top Destination Hosts" \
    "SELECT bro_id_resp_h AS dst, COUNT(*) AS c FROM bro_conn_log GROUP BY dst ORDER BY c DESC LIMIT $TOP_N;"

  run_query "Top DNS Queries" \
    "SELECT bro_query, COUNT(*) AS c FROM bro_dns_log GROUP BY bro_query ORDER BY c DESC LIMIT $TOP_N;"

  run_query "DNS Query Types" \
    "SELECT bro_qtype_name AS qtype, COUNT(*) AS c FROM bro_dns_log GROUP BY qtype ORDER BY c DESC LIMIT $TOP_N;"

  run_query "Top TLS SNI" \
    "SELECT bro_server_name, COUNT(*) AS c FROM bro_ssl_log WHERE bro_server_name IS NOT NULL GROUP BY bro_server_name ORDER BY c DESC LIMIT $TOP_N;"

  run_query "Weird Events" \
    "SELECT bro_name, COUNT(*) AS c FROM bro_weird_log GROUP BY bro_name ORDER BY c DESC LIMIT $TOP_N;"
  exit 0
fi

python3 - "$LOG_DIR" "$TOP_N" <<'PY'
from __future__ import annotations

import ipaddress
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


def parse_log(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    rows: list[dict[str, str]] = []
    fields: list[str] = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not raw:
            continue
        if raw.startswith("#fields"):
            fields = raw.split("\t")[1:]
            continue
        if raw.startswith("#") or not fields:
            continue
        parts = raw.split("\t")
        if len(parts) < len(fields):
            parts.extend([""] * (len(fields) - len(parts)))
        rows.append(dict(zip(fields, parts)))
    return rows


def to_float(value: str | None) -> float | None:
    if value in (None, "", "-"):
        return None
    try:
        return float(value)
    except Exception:
        return None


def to_int(value: str | None) -> int | None:
    if value in (None, "", "-"):
        return None
    try:
        return int(float(value))
    except Exception:
        return None


def ts_iso(value: float | None) -> str:
    if value is None:
        return "unknown"
    return datetime.fromtimestamp(value, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def safe_ip(value: str) -> ipaddress._BaseAddress | None:
    try:
        return ipaddress.ip_address(value)
    except Exception:
        return None


def is_private(value: str) -> bool:
    ip = safe_ip(value)
    return bool(ip and ip.is_private)


def is_external(value: str) -> bool:
    ip = safe_ip(value)
    if ip is None:
        return False
    if ip.is_private or ip.is_multicast or ip.is_loopback or ip.is_unspecified or ip.is_reserved:
        return False
    return True


def top_counter(values: list[str], limit: int) -> list[tuple[str, int]]:
    counter = Counter(v for v in values if v not in ("", "-", None))
    return counter.most_common(limit)


def print_counter(title: str, rows: list[tuple[str, int]]) -> None:
    print(f"\n== {title} ==")
    if not rows:
        print("no data")
        return
    width = max(len(str(count)) for _, count in rows)
    for value, count in rows:
        print(f"{count:>{width}}  {value}")


def print_lines(title: str, rows: list[str]) -> None:
    print(f"\n== {title} ==")
    if not rows:
        print("no data")
        return
    for row in rows:
        print(row)


log_dir = Path(sys.argv[1])
top_n = int(sys.argv[2])

conn = parse_log(log_dir / "conn.log")
dns = parse_log(log_dir / "dns.log")
ssl = parse_log(log_dir / "ssl.log")
weird = parse_log(log_dir / "weird.log")

conn_ts = [to_float(row.get("ts")) for row in conn]
conn_ts = [value for value in conn_ts if value is not None]
present_logs = [name for name in ("conn.log", "dns.log", "ssl.log", "weird.log") if (log_dir / name).exists()]

print("== Zeek Raw Summary ==")
print(f"log_dir={log_dir}")
print(f"logs={', '.join(present_logs) if present_logs else 'none'}")
print(f"window={ts_iso(min(conn_ts) if conn_ts else None)} .. {ts_iso(max(conn_ts) if conn_ts else None)}")
print(f"connections={len(conn)} dns={len(dns)} tls={len(ssl)} weird={len(weird)}")

print_counter("Top Services", top_counter([row.get("service", "") for row in conn], top_n))
print_counter("Top Source Hosts", top_counter([row.get("id.orig_h", "") for row in conn], top_n))
print_counter("Top Destination Hosts", top_counter([row.get("id.resp_h", "") for row in conn], top_n))
print_counter(
    "Top External Destination IPs",
    top_counter([row.get("id.resp_h", "") for row in conn if is_external(row.get("id.resp_h", ""))], top_n),
)
print_counter(
    "Top Internal Talkers",
    top_counter([row.get("id.orig_h", "") for row in conn if is_private(row.get("id.orig_h", ""))], top_n),
)
print_counter("Top DNS Queries", top_counter([row.get("query", "") for row in dns], top_n))
print_counter("DNS Query Types", top_counter([row.get("qtype_name", "") for row in dns], top_n))
print_counter("Top TLS SNI", top_counter([row.get("server_name", "") for row in ssl], top_n))
print_counter("Weird Events", top_counter([row.get("name", "") for row in weird], top_n))

large_transfers: list[tuple[int, str]] = []
for row in conn:
    size = to_int(row.get("orig_bytes"))
    if size is None or size <= 10_000_000:
        continue
    src = row.get("id.orig_h", "unknown")
    dst = row.get("id.resp_h", "unknown")
    large_transfers.append((size, f"{src} -> {dst} bytes={size}"))
large_transfers.sort(reverse=True)
print_lines("Large Outbound Transfers (>10MB)", [line for _, line in large_transfers[:top_n]])

unique_external = sorted({row.get("id.resp_h", "") for row in conn if is_external(row.get("id.resp_h", ""))})
print_lines("Unique External IPs Observed", unique_external[:top_n])
PY
