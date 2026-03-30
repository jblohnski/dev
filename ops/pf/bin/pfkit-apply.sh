#!/usr/bin/env bash
# dev-cmd: alias=pfa name="PF Apply" group=sys run=sudo desc="Render and load pfkit anchor rules"

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
PFCONF="/etc/pf.conf"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing config: $ENV_FILE" >&2
  exit 1
fi

if [[ ! -f "$PFCONF" ]]; then
  echo "Missing pf config: $PFCONF" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# ------------------------------
# Detect network
# ------------------------------
EXT_IF="${EXT_IF:-$(route -n get default | awk '/interface:/{print $2}')}"
ROUTER_IP="$(route -n get default | awk '/gateway:/{print $2}')"

if [[ -z "$EXT_IF" || -z "$ROUTER_IP" ]]; then
  echo "Failed to detect EXT_IF or ROUTER_IP" >&2
  exit 1
fi

# ------------------------------
# DNS mode
# ------------------------------
case "${DNS_MODE:-router}" in
  router)
    DNS_OK="$ROUTER_IP"
    ;;
  direct)
    DNS_OK="${DNS_ALLOWED:-}"
    [[ -z "$DNS_OK" ]] && { echo "DNS_MODE=direct requires DNS_ALLOWED"; exit 1; }
    ;;
  *)
    echo "Invalid DNS_MODE"; exit 1;
    ;;
esac

LAN_NETS="${ALLOW_LAN_CIDRS:-192.168.0.0/16 10.0.0.0/8 172.16.0.0/12}"

# ------------------------------
# Optional rules (multiline-safe)
# ------------------------------

DOT_RULES="# (DoT disabled)"
if [[ "${BLOCK_DOT:-0}" == "1" ]]; then
DOT_RULES=$(cat <<EOF
block return log quick on __EXT_IF__ proto tcp to any port 853
block return log quick on __EXT_IF__ proto udp to any port 853
EOF
)
fi

QUIC_RULES="# (QUIC allowed)"
if [[ "${BLOCK_QUIC:-1}" == "1" ]]; then
QUIC_RULES=$(cat <<EOF
block return log quick on __EXT_IF__ proto udp to any port 443
EOF
)
fi

MDNS_RULES="# (mDNS disabled)"
if [[ "${BLOCK_MDNS:-1}" == "1" ]]; then
MDNS_RULES=$(cat <<EOF
block drop log quick on __EXT_IF__ proto udp to any port 5353
EOF
)
fi

UTUN_RULES="# (No utun interfaces detected at apply time)"
utun_ifaces="$(ifconfig -l | tr ' ' '\n' | awk '/^utun[0-9]+$/')"
if [[ -n "$utun_ifaces" ]]; then
  UTUN_RULES="$(
    while IFS= read -r utun; do
      [[ -n "$utun" ]] || continue
      printf 'block drop log quick on %s all\n' "$utun"
    done <<<"$utun_ifaces"
  )"
fi

# Export for perl
export EXT_IF ROUTER_IP DNS_OK LAN_NETS DOT_RULES QUIC_RULES MDNS_RULES UTUN_RULES

# ------------------------------
# Render (PERL - multiline safe)
# ------------------------------
rendered=$(perl -pe '
s/__DOT_RULES__/$ENV{DOT_RULES}/g;
s/__QUIC_RULES__/$ENV{QUIC_RULES}/g;
s/__MDNS_RULES__/$ENV{MDNS_RULES}/g;
s/__UTUN_RULES__/$ENV{UTUN_RULES}/g;
s/__EXT_IF__/$ENV{EXT_IF}/g;
s/__ROUTER_IP__/$ENV{ROUTER_IP}/g;
s/__DNS_OK__/$ENV{DNS_OK}/g;
s#__LAN_NETS__#$ENV{LAN_NETS}#g;
' "$TEMPLATE")

# ------------------------------
# Write + load
# ------------------------------
printf "%s\n" "$rendered" > "$ANCHOR_DST"
chmod 644 "$ANCHOR_DST"

if ! grep -q '^anchor "pfkit/\*"' "$PFCONF" || ! grep -q '^load anchor "pfkit" from "/etc/pf.anchors/pfkit.anchor"' "$PFCONF"; then
  echo "pfkit is not wired into $PFCONF; run pfkit-install first" >&2
  exit 1
fi

pfctl -a pfkit -nf "$ANCHOR_DST"
pfctl -a pfkit -f "$ANCHOR_DST"
pfctl -e 2>/dev/null || true

# ------------------------------
# Output
# ------------------------------
echo ">> Applied pfkit"
echo "   ext_if   : $EXT_IF"
echo "   router_ip: $ROUTER_IP"
echo "   dns_mode : ${DNS_MODE:-router}"
echo "   dns_ok   : $DNS_OK"
echo "   block_mdns: ${BLOCK_MDNS:-1}"
echo "   block_dot : ${BLOCK_DOT:-0}"
echo "   block_quic: ${BLOCK_QUIC:-1}"
echo "   utuns    : ${utun_ifaces//$'\n'/ }"
echo
echo "Validate:"
echo "  sudo pfctl -s info | sed -n '/^Status:/p'"
echo "  sudo pfctl -sr | grep 'anchor '"
echo "  sudo pfctl -a pfkit -sr"
