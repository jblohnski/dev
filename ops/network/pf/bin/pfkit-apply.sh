#!/usr/bin/env bash
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
GOOGLE_RANGE_HELPER="$ROOT_DIR/bin/pfkit-google-ranges.py"

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

EXT_IF="${EXT_IF:-$(route -n get default | awk '/interface:/{print $2}')}"
ROUTER_IP="$(route -n get default | awk '/gateway:/{print $2}')"

if [[ -z "$EXT_IF" || -z "$ROUTER_IP" ]]; then
  echo "Failed to detect EXT_IF or ROUTER_IP" >&2
  exit 1
fi

case "${DNS_MODE:-router}" in
  router)
    DNS_OK="$ROUTER_IP"
    ;;
  direct)
    DNS_OK="${DNS_ALLOWED:-}"
    [[ -z "$DNS_OK" ]] && { echo "DNS_MODE=direct requires DNS_ALLOWED" >&2; exit 1; }
    ;;
  *)
    echo "Invalid DNS_MODE: ${DNS_MODE:-}" >&2
    exit 1
    ;;
esac

LAN_NETS="${ALLOW_LAN_CIDRS:-192.168.0.0/16 10.0.0.0/8 172.16.0.0/12}"
GOOGLE_ENDPOINT_MODE="${GOOGLE_ENDPOINT_MODE:-official_default_domains}"
GOOGLE_ALLOWED="${GOOGLE_ALLOWED:-${GGC_ALLOWED:-}}"
GOOGLE_ONLY_MODE="${GOOGLE_ONLY_MODE:-0}"
ALLOW_APPLE_P2P="${ALLOW_APPLE_P2P:-1}"
BLOCK_UTUN="${BLOCK_UTUN:-0}"

case "$GOOGLE_ENDPOINT_MODE" in
  official_default_domains)
    if [[ ! -f "$GOOGLE_RANGE_HELPER" ]]; then
      echo "Missing Google range helper: $GOOGLE_RANGE_HELPER" >&2
      exit 1
    fi
    GOOGLE_ALLOWED_RENDERED="$(python3 "$GOOGLE_RANGE_HELPER")"
    [[ -n "$GOOGLE_ALLOWED_RENDERED" ]] || {
      echo "Failed to resolve official Google-owned ranges" >&2
      exit 1
    }
    ;;
  manual)
    GOOGLE_ALLOWED_RENDERED="$GOOGLE_ALLOWED"
    [[ -n "$GOOGLE_ALLOWED_RENDERED" ]] || {
      echo "GOOGLE_ENDPOINT_MODE=manual requires GOOGLE_ALLOWED" >&2
      exit 1
    }
    ;;
  *)
    echo "Invalid GOOGLE_ENDPOINT_MODE: $GOOGLE_ENDPOINT_MODE" >&2
    exit 1
    ;;
esac

DOT_RULES="# (DoT disabled)"
if [[ "${BLOCK_DOT:-0}" == "1" ]]; then
DOT_RULES=$(cat <<EOF
block return log quick on __EXT_IF__ inet proto tcp to any port 853 label "pfkit:dot-block-tcp"
block return log quick on __EXT_IF__ inet proto udp to any port 853 label "pfkit:dot-block-udp"
EOF
)
fi

QUIC_RULES="# (QUIC allowed)"
if [[ "${BLOCK_QUIC:-1}" == "1" ]]; then
QUIC_RULES=$(cat <<EOF
block return log quick on __EXT_IF__ inet proto udp to any port 443 label "pfkit:quic-block"
EOF
)
fi

APPLE_LOCAL_RULES="# (Apple peer / continuity interfaces use default policy)"
if [[ "$ALLOW_APPLE_P2P" == "1" ]]; then
APPLE_LOCAL_RULES=$(cat <<EOF
pass quick on awdl0 all label "pfkit:awdl-pass"
pass quick on llw0 all label "pfkit:llw-pass"
EOF
)
fi

MDNS_RULES=$(cat <<EOF
pass in quick on __EXT_IF__ inet proto udp from any to 224.0.0.251 port 5353 keep state label "pfkit:mdns-pass-in"
pass out quick on __EXT_IF__ inet proto udp to 224.0.0.251 port 5353 keep state label "pfkit:mdns-pass-out"
pass in quick on __EXT_IF__ inet6 proto udp from any to ff02::fb port 5353 keep state label "pfkit:mdns6-pass-in"
pass out quick on __EXT_IF__ inet6 proto udp to ff02::fb port 5353 keep state label "pfkit:mdns6-pass-out"
EOF
)
if [[ "${BLOCK_MDNS:-0}" == "1" ]]; then
MDNS_RULES=$(cat <<EOF
block drop log quick on __EXT_IF__ inet proto udp to any port 5353 label "pfkit:mdns-block"
block drop log quick on __EXT_IF__ inet6 proto udp to any port 5353 label "pfkit:mdns6-block"
EOF
)
fi

UTUN_RULES="# (No utun interfaces detected at apply time)"
utun_ifaces="$(ifconfig -l | tr ' ' '\n' | awk '/^utun[0-9]+$/')"
if [[ -n "$utun_ifaces" ]]; then
  UTUN_RULES="$(
    while IFS= read -r utun; do
      [[ -n "$utun" ]] || continue
      if [[ "$BLOCK_UTUN" == "1" ]]; then
        printf 'block drop log quick on %s all label "pfkit:utun-block:%s"\n' "$utun" "$utun"
      else
        printf 'pass quick on %s all label "pfkit:utun-pass:%s"\n' "$utun" "$utun"
      fi
    done <<<"$utun_ifaces"
  )"
fi

if [[ "$GOOGLE_ONLY_MODE" == "1" ]]; then
EGRESS_RULES=$(cat <<EOF
# Google-only HTTPS lockdown mode
pass out quick on __EXT_IF__ inet proto icmp all keep state label "pfkit:icmp-pass"
pass out quick on __EXT_IF__ inet proto { tcp udp } to <lan_nets> keep state label "pfkit:lan-pass"
pass out quick on __EXT_IF__ inet proto tcp to <google_endpoints> port 443 keep state label "pfkit:google-only-https"
block return log quick on __EXT_IF__ inet proto tcp to any port 443 label "pfkit:https-non-google-block"
pass out quick on __EXT_IF__ inet proto { tcp udp } all keep state label "pfkit:egress-pass-non443"
EOF
)
else
EGRESS_RULES=$(cat <<EOF
# Normal browsing mode
pass out quick on __EXT_IF__ inet proto icmp all keep state label "pfkit:icmp-pass"
pass out quick on __EXT_IF__ inet proto { tcp udp } all keep state label "pfkit:egress-pass"
EOF
)
fi

export EXT_IF ROUTER_IP DNS_OK LAN_NETS GOOGLE_ALLOWED_RENDERED APPLE_LOCAL_RULES DOT_RULES QUIC_RULES MDNS_RULES UTUN_RULES EGRESS_RULES

rendered=$(perl -pe '
s/__APPLE_LOCAL_RULES__/$ENV{APPLE_LOCAL_RULES}/g;
s/__DOT_RULES__/$ENV{DOT_RULES}/g;
s/__QUIC_RULES__/$ENV{QUIC_RULES}/g;
s/__MDNS_RULES__/$ENV{MDNS_RULES}/g;
s/__UTUN_RULES__/$ENV{UTUN_RULES}/g;
s/__EGRESS_RULES__/$ENV{EGRESS_RULES}/g;
s/__EXT_IF__/$ENV{EXT_IF}/g;
s/__ROUTER_IP__/$ENV{ROUTER_IP}/g;
s/__DNS_OK__/$ENV{DNS_OK}/g;
s#__LAN_NETS__#$ENV{LAN_NETS}#g;
s#__GOOGLE_ALLOWED__#$ENV{GOOGLE_ALLOWED_RENDERED}#g;
' "$TEMPLATE")

unresolved_tokens="$(printf '%s\n' "$rendered" | grep -oE '__[A-Z0-9_]+__' | sort -u || true)"
if [[ -n "$unresolved_tokens" ]]; then
  echo "Unresolved pf anchor template tokens:" >&2
  printf '  %s\n' $unresolved_tokens >&2
  exit 1
fi

printf "%s\n" "$rendered" > "$ANCHOR_DST"
chmod 644 "$ANCHOR_DST"

if ! grep -q '^anchor "pfkit"$' "$PFCONF" || ! grep -q '^load anchor "pfkit" from "/etc/pf\.anchors/pfkit\.anchor"' "$PFCONF"; then
  echo "pfkit is not wired into $PFCONF; run pfkit-install first" >&2
  exit 1
fi

pfctl -a pfkit -nf "$ANCHOR_DST"
pfctl -a pfkit -f "$ANCHOR_DST"
pfctl -e 2>/dev/null || true

echo ">> Applied pfkit"
echo "   ext_if     : $EXT_IF"
echo "   router_ip  : $ROUTER_IP"
echo "   dns_mode   : ${DNS_MODE:-router}"
echo "   dns_ok     : $DNS_OK"
echo "   google_mode: $GOOGLE_ENDPOINT_MODE"
echo "   google_only: $GOOGLE_ONLY_MODE"
echo "   allow_p2p  : $ALLOW_APPLE_P2P"
echo "   block_mdns : ${BLOCK_MDNS:-0}"
echo "   block_dot  : ${BLOCK_DOT:-0}"
echo "   block_quic : ${BLOCK_QUIC:-1}"
echo "   block_utun : $BLOCK_UTUN"
echo "   utuns      : ${utun_ifaces//$'\n'/ }"
echo
echo "Validate:"
echo "  sudo pfctl -s info | sed -n '/^Status:/p'"
echo "  sudo pfctl -sr | grep 'anchor '"
echo "  sudo pfctl -a pfkit -sr"
echo "  sudo pfctl -s labels | grep 'pfkit:'"
