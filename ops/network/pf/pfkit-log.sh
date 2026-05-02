#!/usr/bin/env bash
# Internal helper: manage retained PFKit block logs and logger lifecycle.
# Helper for pfkit log capture lifecycle. Intended to be driven by pfkit.sh.

set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit-log: macos only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "run with sudo" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../../.." && pwd)"

resolve_owner() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
    return
  fi
  id -un
}

resolve_owner_home() {
  local owner
  owner="$(resolve_owner)"
  local home=""
  home="$(dscl . -read "/Users/$owner" NFSHomeDirectory 2>/dev/null | awk 'NR==1{print $2}')"
  if [[ -z "$home" ]]; then
    home="${HOME:-/var/root}"
  fi
  printf '%s\n' "$home"
}

legacy_state_dir() {
  printf '%s/Library/Logs/pfkit\n' "$(resolve_owner_home)"
}

state_dir() {
  printf '%s/pfkit\n' "${DEV_LOG_ROOT:-$REPO_ROOT/logs}"
}

pid_file() {
  printf '%s/blocks.pid\n' "$(state_dir)"
}

log_file() {
  printf '%s/blocks.log\n' "$(state_dir)"
}

stderr_file() {
  printf '%s/blocks.stderr.log\n' "$(state_dir)"
}

legacy_pid_file() {
  printf '%s/blocks.pid\n' "$(legacy_state_dir)"
}

legacy_log_file() {
  printf '%s/blocks.log\n' "$(legacy_state_dir)"
}

legacy_stderr_file() {
  printf '%s/blocks.stderr.log\n' "$(legacy_state_dir)"
}

running_pid_from() {
  local pidfile="$1" pid command
  [[ -f "$pidfile" ]] || return 1
  pid="$(<"$pidfile")"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  [[ "$command" == *"pfkit-log.sh run"* ]] || return 1
  printf '%s\n' "$pid"
}

rotate_file() {
  local file="$1" max_bytes="$2" owner size
  [[ -f "$file" ]] || return 0
  size="$(stat -f '%z' "$file" 2>/dev/null || echo 0)"
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  (( size < max_bytes )) && return 0

  rm -f "$file.3"
  [[ -f "$file.2" ]] && mv "$file.2" "$file.3"
  [[ -f "$file.1" ]] && mv "$file.1" "$file.2"
  mv "$file" "$file.1"
  : > "$file"

  owner="$(resolve_owner)"
  chown "$owner":staff "$file" 2>/dev/null || true
}

ensure_state_dir() {
  local dir owner
  dir="$(state_dir)"
  owner="$(resolve_owner)"
  mkdir -p "$dir"
  chown "$owner":staff "$dir" 2>/dev/null || true

  if [[ ! -f "$(log_file)" && -f "$(legacy_log_file)" ]]; then
    cp "$(legacy_log_file)" "$(log_file)"
  fi
  if [[ ! -f "$(stderr_file)" && -f "$(legacy_stderr_file)" ]]; then
    cp "$(legacy_stderr_file)" "$(stderr_file)"
  fi

  touch "$(log_file)" "$(stderr_file)"
  rotate_file "$(log_file)" 5242880
  rotate_file "$(stderr_file)" 1048576
  chown "$owner":staff "$(log_file)" "$(stderr_file)" 2>/dev/null || true
}

log_notice() {
  ensure_state_dir
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$(log_file)"
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

running_pid() {
  running_pid_from "$(pid_file)" && return 0
  running_pid_from "$(legacy_pid_file)"
}

ensure_pflog_interface() {
  if ifconfig pflog0 >/dev/null 2>&1; then
    ifconfig pflog0 up >/dev/null 2>&1 || true
    return 0
  fi

  if ifconfig -C 2>/dev/null | tr ' ' '\n' | grep -qx 'pflog'; then
    ifconfig pflog0 create >/dev/null 2>&1 || true
    if ifconfig pflog0 >/dev/null 2>&1; then
      ifconfig pflog0 up >/dev/null 2>&1 || true
      return 0
    fi
  fi

  return 1
}

start_logger() {
  if running_pid_from "$(pid_file)" >/dev/null 2>&1; then
    printf '%s  %s\n' "$(paint '1;32' running)" "pfkit logger already running"
    printf '  pid : %s\n' "$(running_pid)"
    printf '  log : %s\n' "$(log_file)"
    return
  fi

  if running_pid_from "$(legacy_pid_file)" >/dev/null 2>&1; then
    local legacy_pid
    legacy_pid="$(running_pid_from "$(legacy_pid_file)")"
    printf '%s  legacy logger pid=%s\n' "$(paint '1;33' stopping)" "$legacy_pid"
    kill "$legacy_pid" 2>/dev/null || true
    wait "$legacy_pid" 2>/dev/null || true
    rm -f "$(legacy_pid_file)"
  fi

  if ! ensure_pflog_interface; then
    log_notice "pfkit logger unavailable: pflog0 missing; block capture not started"
    echo "pfkit-log: failed to create or find pflog0; block capture not started" >&2
    echo "  log: $(log_file)" >&2
    exit 1
  fi

  ensure_state_dir
  nohup bash "$0" run >>"$(log_file)" 2>>"$(stderr_file)" </dev/null &
  echo "$!" > "$(pid_file)"
  sleep 1
  if running_pid >/dev/null 2>&1; then
    printf '%s  %s\n' "$(paint '1;32' running)" "pfkit logger started"
    printf '  pid : %s\n' "$(running_pid)"
    printf '  log : %s\n' "$(log_file)"
    printf '  err : %s\n' "$(stderr_file)"
    return
  fi

  echo "pfkit-log: failed to start block logger" >&2
  exit 1
}

stop_logger() {
  local pidfile pid
  pidfile="$(pid_file)"
  if ! pid="$(running_pid)"; then
    rm -f "$pidfile"
    printf '%s  %s\n' "$(paint '1;33' stopped)" "pfkit logger not running"
    return
  fi
  kill -INT "$pid" 2>/dev/null || true
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
  fi
  rm -f "$pidfile"
  printf '%s  %s\n' "$(paint '1;31' stopped)" "pfkit logger stopped"
}

tail_logger() {
  ensure_state_dir
  tail -n "${1:-50}" "$(log_file)"
}

cat_logger() {
  ensure_state_dir
  cat "$(log_file)"
}

report_logger() {
  ensure_state_dir
  python3 - "$(state_dir)" "$(log_file)" "$(stderr_file)" "$(pid_file)" "$(legacy_pid_file)" <<'PY'
from __future__ import annotations

import re
import sys
import os
import subprocess
from collections import Counter
from pathlib import Path

state_dir, log_file, stderr_file, pid_file, legacy_pid_file = map(Path, sys.argv[1:])

block_paths = [log_file, *(state_dir / f"blocks.log.{index}" for index in range(1, 4))]
error_paths = [stderr_file, *(state_dir / f"blocks.stderr.log.{index}" for index in range(1, 4))]


def read_lines(paths: list[Path]) -> list[str]:
    lines: list[str] = []
    for path in paths:
        if not path.is_file():
            continue
        try:
            lines.extend(path.read_text(errors="ignore").splitlines())
        except OSError:
            continue
    return lines


def running_pid(path: Path) -> str:
    try:
        pid = path.read_text().strip()
    except OSError:
        return ""
    if not pid:
        return ""
    try:
        os.kill(int(pid), 0)
    except (OSError, ValueError):
        return ""
    try:
        command = subprocess.check_output(["ps", "-p", pid, "-o", "command="], text=True, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError):
        return ""
    if "pfkit-log.sh run" not in command:
        return ""
    return pid


def expand_count(line: str) -> int:
    match = re.search(r"\s+\[x(\d+)\]\s*$", line)
    if match:
        return int(match.group(1))
    return 1


def clean_line(line: str) -> str:
    return re.sub(r"\s+\[x\d+\]\s*$", "", line.strip())


def first_timestamp(line: str) -> str:
    match = re.match(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", line)
    return match.group(1) if match else ""


def parse_block(line: str) -> dict[str, str] | None:
    line = clean_line(line)
    if " block " not in f" {line.lower()} " and ": block " not in line.lower():
        return None

    direction = "unknown"
    interface = "unknown"
    match = re.search(r": block\s+(in|out)\s+on\s+([^: ]+):\s+", line)
    if match:
        direction = match.group(1)
        interface = match.group(2)

    source = "unknown"
    dest = "unknown"
    flow = re.search(r":\s+([^ ]+)\s+>\s+([^:]+):", line)
    if flow:
        source = normalize_endpoint(flow.group(1))
        dest = normalize_endpoint(flow.group(2))

    lowered = line.lower()
    proto = "other"
    if " udp," in lowered:
        proto = "udp"
    elif " flags [" in lowered:
        proto = "tcp"
    elif " icmp6" in lowered:
        proto = "icmp6"
    elif " icmp" in lowered:
        proto = "icmp"

    reason = "default"
    dest_port = dest.rsplit(":", 1)[1] if ":" in dest and dest.rsplit(":", 1)[1].isdigit() else ""
    if proto == "udp" and dest_port == "443":
        reason = "quic"
    elif dest_port == "853":
        reason = "dot"
    elif dest_port == "5353":
        reason = "mdns"
    elif interface.startswith("utun"):
        reason = "utun"
    elif dest_port == "53":
        reason = "dns"
    elif proto == "udp":
        reason = "udp"
    elif proto == "tcp":
        reason = "tcp"

    return {
        "direction": direction,
        "interface": interface,
        "source": source,
        "dest": dest,
        "proto": proto,
        "reason": reason,
        "timestamp": first_timestamp(line),
        "line": line,
    }


def normalize_endpoint(endpoint: str) -> str:
    endpoint = endpoint.rstrip(":")
    if endpoint.count(".") >= 4:
        host, port = endpoint.rsplit(".", 1)
        if port.isdigit():
            return f"{host}:{port}"
    return endpoint


def print_top(title: str, counter: Counter[str], limit: int = 8) -> None:
    print(section(title))
    if not counter:
        print(dim("  (none)"))
        return
    for value, count in counter.most_common(limit):
        print(f"  {accent(f'{count:>6}')}  {value}")


env = __import__("os").environ
use_color = bool(env.get("FORCE_COLOR")) or (sys.stdout.isatty() and not bool(env.get("NO_COLOR")))


def paint(code: str, text: str) -> str:
    if not use_color:
        return text
    return f"\033[{code}m{text}\033[0m"


def title(text: str) -> str:
    return paint("1;36", text)


def section(text: str) -> str:
    return paint("1;34", text)


def accent(text: str) -> str:
    return paint("1;33", text)


def good(text: str) -> str:
    return paint("1;32", text)


def warn(text: str) -> str:
    return paint("1;31", text)


def dim(text: str) -> str:
    return paint("2", text)


block_lines = read_lines(block_paths)
error_lines = read_lines(error_paths)

events: list[tuple[dict[str, str], int]] = []
for raw in block_lines:
    parsed = parse_block(raw)
    if parsed is None:
        continue
    events.append((parsed, expand_count(raw)))

total_blocks = sum(count for _, count in events)
unique_flows = Counter()
by_reason = Counter()
by_proto = Counter()
by_direction = Counter()
by_interface = Counter()
by_dest = Counter()
by_source = Counter()
first_seen = ""
last_seen = ""

for event, count in events:
    unique_flows[f"{event['proto']} {event['source']} -> {event['dest']}"] += count
    by_reason[event["reason"]] += count
    by_proto[event["proto"]] += count
    by_direction[event["direction"]] += count
    by_interface[event["interface"]] += count
    by_dest[event["dest"]] += count
    by_source[event["source"]] += count
    if event["timestamp"]:
        if not first_seen or event["timestamp"] < first_seen:
            first_seen = event["timestamp"]
        if not last_seen or event["timestamp"] > last_seen:
            last_seen = event["timestamp"]

error_counter = Counter()
packet_counter = Counter()
for raw in error_lines:
    line = raw.strip()
    if not line:
        continue
    received_matches = re.findall(r"(\d+)\s+packets received by filter", line)
    dropped_matches = re.findall(r"(\d+)\s+packets dropped by kernel", line)
    captured_matches = re.findall(r"(\d+)\s+packets captured", line)
    if received_matches:
        packet_counter["packets received"] += sum(int(value) for value in received_matches)
        continue
    if dropped_matches:
        packet_counter["packets dropped"] += sum(int(value) for value in dropped_matches)
        continue
    if captured_matches:
        packet_counter["packets captured"] += sum(int(value) for value in captured_matches)
        continue
    if "listening on pflog0" in line:
        error_counter["tcpdump listening on pflog0"] += 1
    elif "tcpdump:" in line:
        error_counter[line] += 1
    else:
        error_counter[line] += 1

logger = running_pid(pid_file) or running_pid(legacy_pid_file)

received = packet_counter.get("packets received", 0)
dropped = packet_counter.get("packets dropped", 0)
logger_text = logger or "not recorded"
logger_text = good(logger_text) if logger else warn(logger_text)

print(title("pfkit report"))
print(f"  window : {first_seen or 'unknown'} -> {last_seen or 'unknown'}")
print(f"  logs   : {state_dir}")
print(f"  logger : {logger_text}")
print(
    "  totals : "
    f"{accent(str(total_blocks))} blocks, "
    f"{accent(str(len(unique_flows)))} flows, "
    f"{accent(str(sum(error_counter.values())))} logger notes"
)
if packet_counter:
    dropped_text = good(str(dropped)) if dropped == 0 else warn(str(dropped))
    print(f"  tcpdump: {received} received, {dropped_text} dropped")
print()

if total_blocks == 0:
    print(section("summary"))
    print("  no retained pf block events found.")
    print()
else:
    top_reasons = ", ".join(f"{name}={count}" for name, count in by_reason.most_common(4))
    top_dest = by_dest.most_common(1)[0][0] if by_dest else "none"
    top_flow = unique_flows.most_common(1)[0][0] if unique_flows else "none"
    print(section("summary"))
    print(f"  classes : {top_reasons or 'none'}")
    print(f"  target  : {top_dest}")
    print(f"  flow    : {top_flow}")
    print()

print_top("block classes", by_reason, 6)
print()
print_top("interfaces", by_interface, 6)
print()
print_top("top destinations", by_dest, 6)
print()
print_top("top flows", unique_flows, 6)
if error_counter:
    print()
    print_top("logger notes", error_counter, 6)
PY
}

clear_logger() {
  ensure_state_dir
  : > "$(log_file)"
  : > "$(stderr_file)"
  printf '%s  %s\n' "$(paint '1;33' cleared)" "$(log_file)"
}

usage() {
  cat <<'EOF'
usage: pfkit-log.sh [start|stop|tail|cat|path|clear|report] [lines]
EOF
}

run_logger() {
  if ! ifconfig pflog0 >/dev/null 2>&1; then
    echo "pfkit-log: pflog0 missing" >&2
    exit 1
  fi

  local fifo tcpdump_pid
  fifo="${TMPDIR:-/tmp}/pfkit-log.$$.fifo"
  tcpdump_pid=""

  cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [[ -n "$tcpdump_pid" ]] && kill -0 "$tcpdump_pid" 2>/dev/null; then
      kill -INT "$tcpdump_pid" 2>/dev/null || true
      wait "$tcpdump_pid" 2>/dev/null || true
    fi
    rm -f "$fifo"
    exit "$status"
  }

  trap cleanup EXIT INT TERM
  rm -f "$fifo"
  mkfifo "$fifo"
  tcpdump -l -n -e -tttt -i pflog0 > "$fifo" &
  tcpdump_pid=$!

  awk '
    function flush_prev() {
      if (prev == "") {
        return
      }
      if (count > 1) {
        print prev " [x" count "]"
      } else {
        print prev
      }
      fflush()
    }

    {
      lower = tolower($0)
      if (lower !~ /(^|[[:space:]])block([[:space:]]|$)/) {
        next
      }

      if ($0 == prev) {
        count++
        next
      }

      flush_prev()
      prev = $0
      count = 1
    }

    END {
      flush_prev()
    }
  ' < "$fifo"
}

cmd="${1:-report}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  start)
    start_logger
    ;;
  stop)
    stop_logger
    ;;
  tail)
    tail_logger "${1:-50}"
    ;;
  cat)
    cat_logger
    ;;
  report)
    report_logger
    ;;
  path)
    ensure_state_dir
    log_file
    ;;
  clear)
    clear_logger
    ;;
  run)
    run_logger
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
