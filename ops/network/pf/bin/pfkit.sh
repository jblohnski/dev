#!/usr/bin/env bash
# dev-cmd: alias=pfkit name=pfkit group=net run=sudo legend=hide desc="Dispatch pfkit lifecycle commands for apply, status, and global PF shutdown"
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
usage: pfo | pfs | pfk | pf <command>

Short commands (recommended):
  pfo   → apply rules and start logging
  pfs   → show status
  pfk   → disable PF globally and stop logging

Legacy commands (still work):
  pf start|on     → apply
  pf status       → status
  pf stop|kill    → disable PF globally
EOF
}

ensure_wired() {
  [[ -f /etc/pf.conf ]] || return 1
  grep -q '^load anchor "pfkit" from "/etc/pf\.anchors/pfkit\.anchor"' /etc/pf.conf &&
    (
      grep -q '^anchor "pfkit"$' /etc/pf.conf ||
      grep -q '^anchor "pfkit/\*"$' /etc/pf.conf
    )
}

start_pfkit() {
  "$BIN_DIR/pfkit-install.sh"
  "$BIN_DIR/pfkit-apply.sh"
  "$BIN_DIR/pfkit-log.sh" start
}

stop_pfkit() {
  "$BIN_DIR/pfkit-log.sh" stop

  if ensure_wired; then
    printf '%s\n' '# pfkit stopped' > "$ANCHOR_DST"
    chmod 644 "$ANCHOR_DST"
    pfctl -a pfkit -nf "$ANCHOR_DST"
    pfctl -a pfkit -f "$ANCHOR_DST"
  fi

  pfctl -d

  echo ">> pfkit stopped (PF disabled globally)"
  echo "   anchor: $ANCHOR_DST"
  echo "   note  : packet filter is now disabled, not just the pfkit anchor"
}

status_pfkit() {
  "$BIN_DIR/pfkit-status.sh" "$@"
}

cmd="${1:-status}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  pfo|start|on)
    start_pfkit
    ;;
  pfs|status)
    status_pfkit "$@"
    ;;
  pfk|stop|kill|off)
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
