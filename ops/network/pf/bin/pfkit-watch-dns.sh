#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: pfkit-watch-dns.sh [--pf] [--iface IF]
       pfkit-watch-dns.sh IF

Defaults to PF decision logs from pflog0.
Pass a bare interface name or --iface IF to capture raw DNS traffic instead.
EOF
}

mode="pf"
iface=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pf)
      mode="pf"
      shift
      ;;
    --iface)
      [[ $# -ge 2 ]] || {
        echo "pfkit-watch-dns: --iface requires an interface name" >&2
        exit 1
      }
      mode="iface"
      iface="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "pfkit-watch-dns: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      mode="iface"
      iface="$1"
      shift
      ;;
  esac
done

if [[ "$mode" == "pf" ]]; then
  if ! ifconfig pflog0 >/dev/null 2>&1 && ifconfig -C 2>/dev/null | tr ' ' '\n' | grep -qx 'pflog'; then
    ifconfig pflog0 create >/dev/null 2>&1 || true
    ifconfig pflog0 up >/dev/null 2>&1 || true
  fi
  if ! ifconfig pflog0 >/dev/null 2>&1; then
    echo "PF log interface does not exist: pflog0" >&2
    exit 1
  fi
  exec sudo tcpdump -l -n -e -ttt -i pflog0 '(port 53 or port 5353)'
fi

iface="${iface:-en0}"
exec sudo tcpdump -l -n -i "$iface" '(udp port 53 or tcp port 53 or udp port 5353)'
