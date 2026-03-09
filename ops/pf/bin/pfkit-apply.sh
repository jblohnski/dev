#!/usr/bin/env bash
# @desc: Render and load pfkit anchor rules
# @tags: ops pf firewall apply
# @run: sudo

set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit-apply: macOS only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run with sudo" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/pfkit.env"
TEMPLATE="$ROOT_DIR/anchors/pfkit.anchor"
ANCHOR_DST="/etc/pf.anchors/pfkit.anchor"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing config: $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# Auto-detect ext interface (default route)
if [[ -z "${EXT_IF:-}" ]]; then
  EXT_IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' | head -1)
fi

ROUTER_IP=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}' | head -1)

if [[ -z "${EXT_IF:-}" || -z "${ROUTER_IP:-}" ]]; then
  echo "Could not determine EXT_IF or ROUTER_IP (default route)." >&2
  echo "EXT_IF='$EXT_IF' ROUTER_IP='$ROUTER_IP'" >&2
  exit 1
fi

DNS_OK=""
case "${DNS_MODE:-router}" in
  router)
    DNS_OK="$ROUTER_IP"
    ;;
  direct)
    DNS_OK="${DNS_ALLOWED:-}"
    if [[ -z "$DNS_OK" ]]; then
      echo "DNS_MODE=direct requires DNS_ALLOWED" >&2
      exit 1
    fi
    ;;
  *)
    echo "Invalid DNS_MODE: $DNS_MODE (use router|direct)" >&2
    exit 1
    ;;
esac

LAN_NETS="${ALLOW_LAN_CIDRS:-192.168.0.0/16 10.0.0.0/8 172.16.0.0/12}"

# Optional rules
DOT_RULES="# (DoT blocking disabled)"
if [[ "${BLOCK_DOT:-0}" == "1" ]]; then
  DOT_RULES=$'block out quick on $ext_if proto tcp to any port 853\npass  out quick on $ext_if proto tcp to <dns_ok> port 853 keep state'
fi

MDNS_RULES="# (mDNS blocking disabled)"
if [[ "${BLOCK_MDNS:-1}" == "1" ]]; then
  MDNS_RULES=$'block drop out quick on $ext_if proto udp to 224.0.0.251 port 5353\nblock drop out quick on $ext_if proto udp to ff02::fb port 5353'
fi

# Render anchor
rendered=$(cat "$TEMPLATE" \
  | sed "s/__EXT_IF__/${EXT_IF}/g" \
  | sed "s/__ROUTER_IP__/${ROUTER_IP}/g" \
  | sed "s#__DNS_OK__#${DNS_OK}#g" \
  | sed "s#__LAN_NETS__#${LAN_NETS}#g" \
  | awk -v dot="$DOT_RULES" '{gsub(/__DOT_RULES__/, dot); print}' \
  | awk -v mdns="$MDNS_RULES" '{gsub(/__MDNS_RULES__/, mdns); print}'
)

printf "%s\n" "$rendered" > "$ANCHOR_DST"
chmod 644 "$ANCHOR_DST"

# Load pf rules
pfctl -f /etc/pf.conf
pfctl -e 2>/dev/null || true

echo ">> Applied pfkit"
echo "   ext_if   : $EXT_IF"
echo "   router_ip: $ROUTER_IP"
echo "   dns_mode : $DNS_MODE"
echo "   dns_ok   : $DNS_OK"
echo "   block_mdns: ${BLOCK_MDNS:-1}"
echo "   block_dot : ${BLOCK_DOT:-0}"
echo
echo "Validate: sudo pfctl -sr | grep -n pfkit -n || sudo pfctl -sr"
