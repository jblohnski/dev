#!/usr/bin/env bash
# @name: Netshot
# @desc: Capture a short packet trace, run Zeek, and summarize the result
# @cmd: netshot
# @keywords: audit network zeek capture
# @run: sudo

set -euo pipefail

readonly DEFAULT_DURATION=40
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly OUTPUT_DIR="${SCRIPT_DIR}/output"

usage() {
  cat <<'EOF'
Usage: ./netshot.sh [duration]

Capture network traffic for the given duration in seconds (default: 40),
run Zeek against the generated PCAP, and print a short summary.
EOF
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

detect_interface() {
  if [[ -n "${NETSHOT_INTERFACE:-}" ]]; then
    echo "$NETSHOT_INTERFACE"
    return 0
  fi

  local iface=""
  if command -v route >/dev/null 2>&1; then
    iface="$(route -n get default 2>/dev/null | awk '/interface: / { print $2; exit }')"
  fi

  if [[ -z "$iface" ]] && command -v tcpdump >/dev/null 2>&1; then
    iface="$(tcpdump -D 2>/dev/null | awk -F. '$2 !~ /lo0/ { print $2; exit }' | awk '{print $1}')"
  fi

  if [[ -z "$iface" ]]; then
    echo "Unable to determine a capture interface. Set NETSHOT_INTERFACE." >&2
    exit 1
  fi

  echo "$iface"
}

validate_duration() {
  local value="$1"
  if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
    echo "Duration must be a positive integer number of seconds." >&2
    exit 1
  fi
}

capture_pcap() {
  local duration="$1"
  local pcap_path="$2"
  local interface="$3"
  local stderr_path="$4"

  local -a tcpdump_cmd=(tcpdump -i "$interface" -nn -U -w "$pcap_path")
  if [[ "${EUID}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo -v
      tcpdump_cmd=(sudo "${tcpdump_cmd[@]}")
    else
      echo "tcpdump capture requires root privileges or sudo." >&2
      exit 1
    fi
  fi

  echo "Capturing traffic on ${interface} for ${duration}s..."
  "${tcpdump_cmd[@]}" >/dev/null 2>"$stderr_path" &
  local tcpdump_pid=$!
  trap 'kill -INT "$tcpdump_pid" >/dev/null 2>&1 || true' INT TERM

  sleep "$duration"

  kill -INT "$tcpdump_pid" >/dev/null 2>&1 || true
  wait "$tcpdump_pid" || true
  trap - INT TERM

  if [[ ! -f "$pcap_path" ]]; then
    echo "tcpdump did not produce a capture file." >&2
    if [[ -s "$stderr_path" ]]; then
      cat "$stderr_path" >&2
    fi
    exit 1
  fi
}

run_zeek() {
  local pcap_path="$1"
  local zeek_dir="$2"

  mkdir -p "$zeek_dir"
  (
    cd "$zeek_dir"
    zeek -C -r "$pcap_path" LogAscii::use_json=T >/dev/null
  )
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local duration="${1:-$DEFAULT_DURATION}"
  validate_duration "$duration"

  require_command tcpdump
  require_command zeek
  require_command python3

  mkdir -p "$OUTPUT_DIR"

  local timestamp
  timestamp="$(date +"%Y%m%d-%H%M%S")"

  local run_dir="${OUTPUT_DIR}/${timestamp}"
  local pcap_path="${run_dir}/capture.pcap"
  local tcpdump_stderr="${run_dir}/tcpdump.stderr.log"
  local zeek_dir="${run_dir}/zeek"
  local interface

  mkdir -p "$run_dir"
  interface="$(detect_interface)"

  capture_pcap "$duration" "$pcap_path" "$interface" "$tcpdump_stderr"

  echo "Running Zeek analysis..."
  run_zeek "$pcap_path" "$zeek_dir"

  echo "Generating summary..."
  python3 "${SCRIPT_DIR}/analyze.py" "$zeek_dir"

  echo
  echo "Artifacts written to ${run_dir}"
}

main "$@"
