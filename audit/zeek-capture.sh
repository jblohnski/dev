#!/usr/bin/env bash
# dev-cmd: alias=zc name="Zeek Capture" group=audit run=user legend=hide desc="Start, stop, and inspect background Zeek capture writing logs to the configured log dir"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$ROOT_DIR/state"
DEFAULT_LOG_DIR="${ZEEK_LOG_DIR:-${DEV_LOG_ROOT:-$ROOT_DIR/../logs}/zeek}"
PID_FILE="${ZEEK_CAPTURE_PID_FILE:-$STATE_DIR/zeek-capture.pid}"
OUT_FILE="${ZEEK_CAPTURE_OUT:-$DEFAULT_LOG_DIR/zeek-capture.out}"
IFACE_DEFAULT="${ZEEK_CAPTURE_IFACE:-}"

usage() {
  cat <<EOF
Usage:
  ./zeek-capture.sh start <iface> [-- zeek args...]
  ./zeek-capture.sh stop
  ./zeek-capture.sh status

Env overrides:
  ZEEK_LOG_DIR=/absolute/path
  DEV_LOG_ROOT=/absolute/path/to/dev/logs
  ZEEK_CAPTURE_IFACE=en0
  ZEEK_CAPTURE_PID_FILE=$STATE_DIR/zeek-capture.pid
  ZEEK_CAPTURE_OUT=$DEFAULT_LOG_DIR/zeek-capture.out

Start behavior:
  sudo zeek -i <iface> -C "Log::default_logdir=<log_dir>" [extra args...]

Examples:
  ./zeek-capture.sh start en0
  ./zeek-capture.sh start en0 -- Site::local_nets+=192.168.1.0/24
  ZEEK_LOG_DIR=$ROOT_DIR/../logs/zeek ./zeek-capture.sh start en0
  ./zeek-capture.sh status
  ./zeek-capture.sh stop
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

pid_is_running() {
  local pid="$1"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

read_pid() {
  [[ -f "$PID_FILE" ]] || return 1
  tr -d '[:space:]' < "$PID_FILE"
}

start_capture() {
  local iface="$1"
  shift
  local extra_args=("$@")
  local log_dir="$DEFAULT_LOG_DIR"

  [[ -n "$iface" ]] || {
    echo "error: interface required" >&2
    usage >&2
    exit 2
  }

  need_cmd zeek
  need_cmd sudo

  mkdir -p "$STATE_DIR" "$log_dir"

  if existing_pid="$(read_pid 2>/dev/null || true)" && pid_is_running "$existing_pid"; then
    echo "Zeek capture already running: pid=$existing_pid"
    echo "log_dir=$log_dir"
    exit 0
  fi

  sudo nohup zeek -i "$iface" -C "Log::default_logdir=$log_dir" \
    "${extra_args[@]}" > "$OUT_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"

  echo "Zeek capture started"
  echo "pid=$pid"
  echo "iface=$iface"
  echo "log_dir=$log_dir"
  echo "stdout_stderr=$OUT_FILE"
}

stop_capture() {
  need_cmd sudo

  local pid
  pid="$(read_pid)" || {
    echo "Zeek capture is not running"
    return 0
  }

  if pid_is_running "$pid"; then
    sudo kill "$pid"
    echo "Zeek capture stopped: pid=$pid"
  else
    echo "Zeek capture pid file was stale: pid=$pid"
  fi

  rm -f "$PID_FILE"
}

status_capture() {
  local pid
  local log_dir="$DEFAULT_LOG_DIR"

  if pid="$(read_pid 2>/dev/null || true)" && pid_is_running "$pid"; then
    echo "status=running"
    echo "pid=$pid"
  else
    echo "status=stopped"
    [[ -n "${pid:-}" ]] && echo "stale_pid=$pid"
  fi

  echo "log_dir=$log_dir"
  echo "stdout_stderr=$OUT_FILE"
  if [[ -d "$log_dir" ]]; then
    find "$log_dir" -maxdepth 1 -type f | sort
  fi
}

cmd="${1:-}"
case "$cmd" in
  start)
    shift
    iface="${1:-$IFACE_DEFAULT}"
    if [[ "${1:-}" == "--" ]]; then
      iface="$IFACE_DEFAULT"
    elif [[ $# -gt 0 ]]; then
      shift
    fi

    extra=()
    if [[ "${1:-}" == "--" ]]; then
      shift
      extra=("$@")
    elif [[ $# -gt 0 ]]; then
      echo "error: extra Zeek args must follow '--'" >&2
      usage >&2
      exit 2
    fi

    start_capture "$iface" "${extra[@]}"
    ;;
  stop)
    stop_capture
    ;;
  status)
    status_capture
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "error: unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
