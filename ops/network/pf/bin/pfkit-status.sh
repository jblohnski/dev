#!/usr/bin/env bash
# dev-cmd: alias=pfkit.status name="pfkit status" group=net run=sudo legend=hide desc="Show PF, pfkit, and logger state plus recent blocked flows"
set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit-status: macOS only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/config/pfkit.env"

resolve_owner() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
    return
  fi
  id -un
}

resolve_owner_home() {
  local owner home
  owner="$(resolve_owner)"
  home="$(dscl . -read "/Users/$owner" NFSHomeDirectory 2>/dev/null | awk 'NR==1{print $2}')"
  if [[ -z "$home" ]]; then
    home="${HOME:-/var/root}"
  fi
  printf '%s\n' "$home"
}

LOG_DIR="${DEV_LOG_ROOT:-$REPO_ROOT/logs}/pfkit"
LEGACY_LOG_DIR="$(resolve_owner_home)/Library/Logs/pfkit"
LOG_FILE="$LOG_DIR/blocks.log"
LOG_PID="$LOG_DIR/blocks.pid"
LEGACY_LOG_PID="$LEGACY_LOG_DIR/blocks.pid"
GOOGLE_HOSTS_FILE="$LOG_DIR/google-hosts.json"
LEGACY_GOOGLE_RANGES_FILE="$LOG_DIR/google-ranges.json"
EXTRA_HTTPS_FILE="$LOG_DIR/extra-https-hosts.json"
LOG_LINES="${PFKIT_STATUS_LOG_LINES:-200}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

EXT_IF_RESOLVED="${EXT_IF:-$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')}"
ROUTER_IP_RESOLVED="$(route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')"

TAIL_MODE=0
SHOW_CIDRS=0
TAIL_LINES=50
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tail)
      TAIL_MODE=1
      if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
        TAIL_LINES="$2"
        shift 2
      else
        shift
      fi
      ;;
    --cidrs)
      SHOW_CIDRS=1
      shift
      ;;
    *)
      echo "pfkit-status: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

status_line="$(pfctl -q -s info | sed -n '/^Status:/p')"
pfkit_rules="$(pfctl -q -a pfkit -sr || true)"

pf_status="off"
if [[ "$status_line" == *"Enabled"* ]]; then
  pf_status="on"
fi

pfkit_status="off"
if [[ -n "$pfkit_rules" ]]; then
  pfkit_status="on"
fi

logger_status="stopped"
if [[ -f "$LOG_PID" ]] && kill -0 "$(cat "$LOG_PID")" 2>/dev/null; then
  logger_status="running"
elif [[ -f "$LEGACY_LOG_PID" ]] && kill -0 "$(cat "$LEGACY_LOG_PID")" 2>/dev/null; then
  logger_status="running (legacy)"
elif ! ifconfig pflog0 >/dev/null 2>&1; then
  logger_status="unavailable (pflog0 missing)"
fi

overall_status="off"
if [[ "$pf_status" == "on" && "$pfkit_status" == "on" ]]; then
  overall_status="on"
fi

if [[ "$TAIL_MODE" == "1" ]]; then
  echo "PF"
  echo "  status: $overall_status"
  echo "  logger: $logger_status"
  echo "  log file: $LOG_FILE"
  echo
  echo "Log Output"
  if [[ ! -f "$LOG_FILE" ]]; then
    echo "(missing)"
  elif [[ ! -s "$LOG_FILE" ]]; then
    echo "(empty)"
  else
    tail -n "$TAIL_LINES" "$LOG_FILE"
  fi
  exit 0
fi

if [[ -n "${BLOCK_APPLE_P2P+x}" ]]; then
  BLOCK_APPLE_P2P_RESOLVED="${BLOCK_APPLE_P2P}"
elif [[ -n "${ALLOW_APPLE_P2P+x}" ]]; then
  if [[ "${ALLOW_APPLE_P2P}" == "1" ]]; then
    BLOCK_APPLE_P2P_RESOLVED="0"
  else
    BLOCK_APPLE_P2P_RESOLVED="1"
  fi
else
  BLOCK_APPLE_P2P_RESOLVED="1"
fi

python3 - "$status_line" "$pfkit_rules" "$LOG_FILE" "$GOOGLE_HOSTS_FILE" "$LEGACY_GOOGLE_RANGES_FILE" "$EXTRA_HTTPS_FILE" "$logger_status" "$overall_status" "$EXT_IF_RESOLVED" "$ROUTER_IP_RESOLVED" "${DNS_MODE:-router}" "${DNS_ALLOWED:-}" "${BASELINE_PROFILE:-unset}" "${GOOGLE_ONLY_MODE:-0}" "${BLOCK_APPLE_P2P_RESOLVED}" "${BLOCK_MDNS:-1}" "${BLOCK_UTUN:-1}" "${BLOCK_QUIC:-1}" "${BLOCK_DOT:-1}" "${GOOGLE_ENDPOINT_MODE:-hosts}" "${GOOGLE_ALLOWED_HOSTS:-}" "${EXTRA_HTTPS_ALLOWED_HOSTS:-}" "${BLACKLIST_IN_CIDRS:-}" "${BLACKLIST_OUT_CIDRS:-}" "${ALLOW_TCP_PORTS:-22 80 443}" "${ALLOW_UDP_PORTS:-}" "${BLOCK_ARBITRARY_UDP:-1}" "$SHOW_CIDRS" "$LOG_LINES" <<'PY'
from __future__ import annotations

import json
import re
import sys
import textwrap
from collections import Counter
from pathlib import Path

(
    status_line,
    pfkit_rules,
    log_file,
    google_hosts_file,
    legacy_google_ranges_file,
    extra_https_file,
    logger_status,
    overall_status,
    ext_if,
    router_ip,
    dns_mode,
    dns_allowed,
    baseline_profile,
    google_only_mode,
    block_apple_p2p,
    block_mdns,
    block_utun,
    block_quic,
    block_dot,
    google_endpoint_mode,
    google_allowed_hosts,
    extra_https_allowed_hosts,
    blacklist_in_cidrs,
    blacklist_out_cidrs,
    allow_tcp_ports,
    allow_udp_ports,
    block_arbitrary_udp,
    show_cidrs,
    log_lines,
) = sys.argv[1:]

log_path = Path(log_file)
google_path = Path(google_hosts_file if Path(google_hosts_file).is_file() else legacy_google_ranges_file)
extra_https_path = Path(extra_https_file)
recent = []
if log_path.is_file():
    try:
        recent = log_path.read_text(errors="ignore").splitlines()[-int(log_lines):]
    except Exception:
        recent = []

def normalize_line(line: str) -> str:
    return re.sub(r"\s+\[x\d+\]$", "", line.strip())

def classify(line: str) -> str:
    lowered = line.lower()
    if " udp," in lowered:
        return "udp"
    if "flags [" in lowered:
        return "tcp"
    if "icmp6" in lowered:
        return "icmp6"
    return "other"

def parse_dest(token: str) -> str:
    token = token.rstrip(":")
    if "." in token:
        host, maybe_port = token.rsplit(".", 1)
        if maybe_port.isdigit():
            return f"{host}:{maybe_port}"
    return token

flow_counts: Counter[str] = Counter()
for raw in recent:
    line = normalize_line(raw)
    if " > " not in line:
        continue
    try:
        rhs = line.split(" > ", 1)[1]
        dest_token = rhs.split(":", 1)[0]
    except Exception:
        continue
    flow_counts[f"{classify(line)} {parse_dest(dest_token)}"] += 1

google_meta = {}
if google_path.is_file():
    try:
        google_meta = json.loads(google_path.read_text())
    except Exception:
        google_meta = {}

extra_https_meta = {}
if extra_https_path.is_file():
    try:
        extra_https_meta = json.loads(extra_https_path.read_text())
    except Exception:
        extra_https_meta = {}

ranges = google_meta.get("ranges", [])
range_count = google_meta.get("range_count", len(ranges))
google_hosts = google_meta.get("hosts") or google_allowed_hosts.split()
google_ranges_text = " ".join(ranges)
extra_ranges = extra_https_meta.get("ranges", [])
extra_ranges_text = " ".join(extra_ranges)

def print_wrapped(label: str, text: str) -> None:
    if not text:
        print(f"{label}(none)")
        return
    for idx, line in enumerate(textwrap.wrap(text, width=100, break_long_words=False), start=1):
        current = label if idx == 1 else " " * len(label)
        print(f"{current}{line}")

print("PF")
print(f"  status   : {overall_status}")
print(f"  logger   : {logger_status}")
print(f"  ext_if   : {ext_if or 'unknown'}")
print(f"  router   : {router_ip or 'unknown'}")
print(f"  dns      : {dns_mode} {dns_allowed}".rstrip())
print(f"  baseline : {baseline_profile}")
print(
    "  profile  : "
    f"google_only={google_only_mode} block_p2p={block_apple_p2p} "
    f"mdns={block_mdns} utun={block_utun} quic={block_quic} "
    f"dot={block_dot} udp_block={block_arbitrary_udp}"
)
print_wrapped("  tcp      : ", allow_tcp_ports)
print_wrapped("  udp      : ", allow_udp_ports if allow_udp_ports else "dns-only")
print(f"  google_m : {google_endpoint_mode}")
print(f"  google   : {len(google_hosts)} hosts / {range_count} IPs")
print_wrapped("  ghosts   : ", " ".join(google_hosts))
print(f"  extra    : {len((extra_https_allowed_hosts or '').split())} hosts / {len(extra_ranges)} IPs")
if extra_https_allowed_hosts:
    print_wrapped("  ehosts   : ", extra_https_allowed_hosts)
print(f"  bl_in    : {len((blacklist_in_cidrs or '').split())} entries")
if blacklist_in_cidrs:
    print_wrapped("  blin_ip  : ", blacklist_in_cidrs)
print(f"  bl_out   : {len((blacklist_out_cidrs or '').split())} entries")
if blacklist_out_cidrs:
    print_wrapped("  blout_ip : ", blacklist_out_cidrs)
if show_cidrs == "1":
    print_wrapped("  gip      : ", google_ranges_text)
    print_wrapped("  eip      : ", extra_ranges_text)
print(f"  log      : {log_file}")
print()
print("Recent Blocks")
if not recent:
    print("  (no log data)")
else:
    print(f"  lines    : {len(recent)}")
    print(f"  unique   : {len(flow_counts)} flows")
    for flow, count in flow_counts.most_common(8):
        print(f"  top      : {flow} x{count}")
PY
