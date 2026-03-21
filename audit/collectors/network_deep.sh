#!/usr/bin/env bash
# dev-cmd: alias=network_deep name="Network Deep" group=audit run=sudo legend=hide desc="Run deep network audit baseline and compare flow"

set -euo pipefail

# Network-focused audit (burst sampling + process attribution + timing distribution)
# Requires: python3, lsof, tcpdump (tcpdump may require sudo).

usage() {
  cat <<EOF
Usage:
  ./net_audit.sh baseline [-- <maudit.py args>]
  ./net_audit.sh compare  [-- <maudit.py args>]

Examples:
  sudo ./net_audit.sh baseline
  sudo ./net_audit.sh compare

Pass-through options (after --) go to maudit.py:
  --burst-seconds N
  --bursts N
  --jitter-min-s X
  --jitter-max-s X
  --interfaces en0 utun2
EOF
}

cmd="${1:-}"
shift || true

case "${cmd}" in
  baseline|compare)
    if [[ "${1:-}" == "--" ]]; then
      shift
    fi
    exec ./maudit.py "${cmd}" "$@"
    ;;
  -h|--help|"")
    usage
    exit 0
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    usage >&2
    exit 2
    ;;
esac
