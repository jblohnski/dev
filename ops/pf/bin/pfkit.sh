#!/usr/bin/env bash
# dev-cmd: alias=pf name="PF Control" group=sys run=sudo desc="Control pfkit lifecycle and block-log capture"

set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit: macOS only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
ANCHOR_DST="/etc/pf.anchors/pfkit.anchor"

usage() {
  cat <<'EOF'
usage: pf <command> [args]

commands:
  start           install wiring if needed, then apply the tracked pfkit rules
  stop            unload pfkit rules from the pfkit anchor without disabling PF globally
  status          show pfkit status plus block-log capture status
  update          re-render and reload the tracked pfkit anchor
  revert          restore the system pf.conf state and remove pfkit wiring
  logs            tail the block log file (default 50 lines)
  logs start      start background block logging from pflog0 into a file
  logs stop       stop background block logging
  logs status     show logger status and log file paths
  logs cat        print the whole block log file
  logs path       print the block log file path
  logs clear      truncate block log files
  dns [args]      run the PF/raw DNS watcher
  blocks          run the live PF block tail
EOF
}

ensure_wired() {
  [[ -f /etc/pf.conf ]] || return 1
  grep -q '^anchor "pfkit/\*"' /etc/pf.conf &&
    grep -q '^load anchor "pfkit" from "/etc/pf.anchors/pfkit.anchor"' /etc/pf.conf
}

start_pfkit() {
  "$BIN_DIR/pfkit-install.sh"
  "$BIN_DIR/pfkit-apply.sh"
}

stop_pfkit() {
  if ! ensure_wired; then
    echo "pfkit stop: pfkit is not installed in /etc/pf.conf" >&2
    exit 1
  fi

  printf '%s\n' '# pfkit stopped' > "$ANCHOR_DST"
  chmod 644 "$ANCHOR_DST"
  pfctl -a pfkit -nf "$ANCHOR_DST"
  pfctl -a pfkit -f "$ANCHOR_DST"
  echo ">> pfkit stopped"
  echo "   anchor: $ANCHOR_DST"
  echo "   note  : existing PF states may continue until they expire"
}

status_pfkit() {
  "$BIN_DIR/pfkit-status.sh"
}

cmd="${1:-status}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  start)
    start_pfkit
    ;;
  stop)
    stop_pfkit
    ;;
  status)
    status_pfkit
    ;;
  update)
    "$BIN_DIR/pfkit-apply.sh" "$@"
    ;;
  revert|uninstall)
    "$BIN_DIR/pfkit-uninstall.sh" "$@"
    ;;
  logs)
    if [[ $# -eq 0 ]]; then
      "$BIN_DIR/pfkit-log.sh" tail
    else
      "$BIN_DIR/pfkit-log.sh" "$@"
    fi
    ;;
  dns)
    "$BIN_DIR/pfkit-watch-dns.sh" "$@"
    ;;
  blocks)
    "$BIN_DIR/pfkit-watch-blocks.sh" "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
