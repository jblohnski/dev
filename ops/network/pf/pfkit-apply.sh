#!/usr/bin/env bash
# Internal helper: render the tracked pfkit anchor from config and load it into PF.
set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pfkit-apply: macos only" >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "run with sudo" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/pfkit.env"
TEMPLATE="$ROOT_DIR/pfkit.anchor"
ANCHOR_DST="/etc/pf.anchors/pfkit.anchor"
PFCONF="/etc/pf.conf"
STATE_DIR="${DEV_LOG_ROOT:-$REPO_ROOT/logs}/pfkit"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing config: $ENV_FILE" >&2
  exit 1
fi

if [[ ! -f "$PFCONF" ]]; then
  echo "missing pf config: $PFCONF" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

resolve_hosts() {
  local state_name="$1"
  shift
  python3 - "$STATE_DIR" "$state_name" "$@" <<'PY'
from __future__ import annotations

import json
import socket
import sys
from ipaddress import IPv4Network
from pathlib import Path

state_dir = Path(sys.argv[1])
state_name = sys.argv[2]
hosts = sys.argv[3:]

ranges: list[str] = []
resolved: dict[str, list[str]] = {}
failures: dict[str, str] = {}

for host in hosts:
    try:
        ips = sorted(
            {
                item[4][0]
                for item in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
                if ":" not in item[4][0]
            }
        )
    except socket.gaierror as error:
        failures[host] = str(error)
        continue
    if not ips:
        failures[host] = "no ipv4 addresses"
        continue
    resolved[host] = ips
    ranges.extend(str(IPv4Network(f"{ip}/32")) for ip in ips)

if state_dir:
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / state_name).write_text(
        json.dumps({"resolved": resolved, "failures": failures}, indent=2, sort_keys=True) + "\n"
    )

for host, reason in failures.items():
    print(f"pfkit-resolve: {host}: {reason}", file=sys.stderr)

print(" ".join(sorted(set(ranges))))
PY
}

EXT_IF="${EXT_IF:-$(route -n get default | awk '/interface:/{print $2}')}"
ROUTER_IP="$(route -n get default | awk '/gateway:/{print $2}')"

if [[ -z "$EXT_IF" || -z "$ROUTER_IP" ]]; then
  echo "failed to detect ext_if or router_ip" >&2
  exit 1
fi

case "${DNS_MODE:-router}" in
  router)
    DNS_OK="$ROUTER_IP"
    ;;
  direct)
    DNS_OK="${DNS_ALLOWED:-}"
    [[ -z "$DNS_OK" ]] && { echo "dns_mode=direct requires dns_allowed" >&2; exit 1; }
    ;;
  *)
    echo "invalid dns_mode: ${DNS_MODE:-}" >&2
    exit 1
    ;;
esac

LAN_NETS="${ALLOW_LAN_CIDRS:-192.168.0.0/16 10.0.0.0/8 172.16.0.0/12}"
DEFAULT_GOOGLE_ALLOWED_HOSTS="accounts.google.com ssl.gstatic.com www.gstatic.com"
GOOGLE_ENDPOINT_MODE="${GOOGLE_ENDPOINT_MODE:-hosts}"
GOOGLE_ALLOWED="${GOOGLE_ALLOWED:-${GGC_ALLOWED:-}}"
GOOGLE_ALLOWED_HOSTS="${GOOGLE_ALLOWED_HOSTS:-$DEFAULT_GOOGLE_ALLOWED_HOSTS}"
EXTRA_HTTPS_ALLOWED="${EXTRA_HTTPS_ALLOWED:-}"
EXTRA_HTTPS_ALLOWED_HOSTS="${EXTRA_HTTPS_ALLOWED_HOSTS:-}"
BLACKLIST_IN_CIDRS="${BLACKLIST_IN_CIDRS:-}"
BLACKLIST_OUT_CIDRS="${BLACKLIST_OUT_CIDRS:-}"
ALLOW_TCP_PORTS_RAW="${ALLOW_TCP_PORTS:-22 80 443}"
ALLOW_UDP_PORTS_RAW="${ALLOW_UDP_PORTS:-}"
GOOGLE_ONLY_MODE="${GOOGLE_ONLY_MODE:-0}"
BLOCK_ARBITRARY_UDP="${BLOCK_ARBITRARY_UDP:-1}"
BLOCK_UTUN="${BLOCK_UTUN:-0}"
BASELINE_PROFILE="${BASELINE_PROFILE:-unset}"

if [[ -n "${BLOCK_APPLE_P2P+x}" ]]; then
  BLOCK_APPLE_P2P="${BLOCK_APPLE_P2P}"
elif [[ -n "${ALLOW_APPLE_P2P+x}" ]]; then
  if [[ "${ALLOW_APPLE_P2P}" == "1" ]]; then
    BLOCK_APPLE_P2P="0"
  else
    BLOCK_APPLE_P2P="1"
  fi
else
  BLOCK_APPLE_P2P="1"
fi

GOOGLE_ALLOWED_RENDERED="127.0.0.1/32"
EXTRA_HTTPS_HOSTS_RENDERED=""
if [[ "$GOOGLE_ONLY_MODE" == "1" ]]; then
  case "$GOOGLE_ENDPOINT_MODE" in
    official_default_domains|hosts)
      GOOGLE_ALLOWED_RENDERED="$(resolve_hosts google-hosts.json $GOOGLE_ALLOWED_HOSTS)"
      [[ -n "$GOOGLE_ALLOWED_RENDERED" ]] || {
        echo "google_endpoint_mode=$GOOGLE_ENDPOINT_MODE requires resolvable google_allowed_hosts" >&2
        exit 1
      }
      ;;
    manual)
      GOOGLE_ALLOWED_RENDERED="$GOOGLE_ALLOWED"
      [[ -n "$GOOGLE_ALLOWED_RENDERED" ]] || {
        echo "google_endpoint_mode=manual requires google_allowed" >&2
        exit 1
      }
      ;;
    *)
      echo "invalid google_endpoint_mode: $GOOGLE_ENDPOINT_MODE" >&2
      exit 1
      ;;
  esac

  if [[ -n "$EXTRA_HTTPS_ALLOWED_HOSTS" ]]; then
    EXTRA_HTTPS_HOSTS_RENDERED="$(resolve_hosts extra-https-hosts.json $EXTRA_HTTPS_ALLOWED_HOSTS 2>/dev/null || true)"
  fi
fi

EXTRA_HTTPS_ALLOWED_RENDERED="$(printf '%s %s\n' "$EXTRA_HTTPS_ALLOWED" "$EXTRA_HTTPS_HOSTS_RENDERED" | xargs echo 2>/dev/null || true)"
ALLOW_TCP_PORTS_RENDERED="$(printf '%s\n' "$ALLOW_TCP_PORTS_RAW" | xargs echo 2>/dev/null || true)"
ALLOW_UDP_PORTS_RENDERED="$(printf '%s\n' "$ALLOW_UDP_PORTS_RAW" | xargs echo 2>/dev/null || true)"
TCP_NON_HTTPS_ALLOWED_PORTS=""
for port in $ALLOW_TCP_PORTS_RENDERED; do
  [[ "$port" == "443" ]] && continue
  TCP_NON_HTTPS_ALLOWED_PORTS="${TCP_NON_HTTPS_ALLOWED_PORTS:+$TCP_NON_HTTPS_ALLOWED_PORTS }$port"
done

EXTRA_HTTPS_TABLE="# (No extra HTTPS endpoint exceptions)"
EXTRA_HTTPS_RULES="# (No extra HTTPS endpoint exceptions)"
if [[ -n "$EXTRA_HTTPS_ALLOWED_RENDERED" ]]; then
  EXTRA_HTTPS_TABLE="table <extra_https_endpoints> persist { $EXTRA_HTTPS_ALLOWED_RENDERED }"
  EXTRA_HTTPS_RULES='pass out quick on __EXT_IF__ inet proto tcp to <extra_https_endpoints> port 443 keep state label "pfkit:extra-https-pass"'
fi

TCP_EGRESS_RULES="# (No general TCP egress ports configured)"
if [[ -n "$ALLOW_TCP_PORTS_RENDERED" ]]; then
  TCP_EGRESS_RULES="pass out quick on __EXT_IF__ inet proto tcp to any port { $ALLOW_TCP_PORTS_RENDERED } keep state label \"pfkit:tcp-egress-pass\""
fi

TCP_NON_HTTPS_EGRESS_RULES="# (No non-HTTPS TCP egress ports configured)"
if [[ -n "$TCP_NON_HTTPS_ALLOWED_PORTS" ]]; then
  TCP_NON_HTTPS_EGRESS_RULES="pass out quick on __EXT_IF__ inet proto tcp to any port { $TCP_NON_HTTPS_ALLOWED_PORTS } keep state label \"pfkit:tcp-nonhttps-pass\""
fi

UDP_EGRESS_RULES="# (Arbitrary UDP blocked)"
if [[ "$BLOCK_ARBITRARY_UDP" == "1" ]]; then
  if [[ -n "$ALLOW_UDP_PORTS_RENDERED" ]]; then
    UDP_EGRESS_RULES="$(cat <<EOF
pass out quick on __EXT_IF__ inet proto udp to any port { $ALLOW_UDP_PORTS_RENDERED } keep state label "pfkit:udp-port-pass"
block return log quick on __EXT_IF__ inet proto udp to any label "pfkit:udp-egress-block"
EOF
)"
  else
    UDP_EGRESS_RULES='block return log quick on __EXT_IF__ inet proto udp to any label "pfkit:udp-egress-block"'
  fi
else
  UDP_EGRESS_RULES='pass out quick on __EXT_IF__ inet proto udp all keep state label "pfkit:udp-egress-pass"'
fi

BLACKLIST_TABLES="# (No blacklist tables)"
BLACKLIST_RULES="# (No blacklist rules)"
if [[ -n "$BLACKLIST_IN_CIDRS" || -n "$BLACKLIST_OUT_CIDRS" ]]; then
  blacklist_tables=()
  blacklist_rules=()
  if [[ -n "$BLACKLIST_IN_CIDRS" ]]; then
    blacklist_tables+=("table <blacklist_in> persist { $BLACKLIST_IN_CIDRS }")
    blacklist_rules+=('block drop log quick on __EXT_IF__ from <blacklist_in> to any label "pfkit:blacklist-in"')
  fi
  if [[ -n "$BLACKLIST_OUT_CIDRS" ]]; then
    blacklist_tables+=("table <blacklist_out> persist { $BLACKLIST_OUT_CIDRS }")
    blacklist_rules+=('block return log quick on __EXT_IF__ from any to <blacklist_out> label "pfkit:blacklist-out"')
  fi
  BLACKLIST_TABLES="$(printf '%s\n' "${blacklist_tables[@]}")"
  BLACKLIST_RULES="$(printf '%s\n' "${blacklist_rules[@]}")"
fi

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
if [[ "$BLOCK_APPLE_P2P" != "1" ]]; then
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
${EXTRA_HTTPS_RULES}
block return log quick on __EXT_IF__ inet proto tcp to any port 443 label "pfkit:https-non-google-block"
${TCP_NON_HTTPS_EGRESS_RULES}
${UDP_EGRESS_RULES}
EOF
)
else
EGRESS_RULES=$(cat <<EOF
# Strict egress mode
pass out quick on __EXT_IF__ inet proto icmp all keep state label "pfkit:icmp-pass"
pass out quick on __EXT_IF__ inet proto { tcp udp } to <lan_nets> keep state label "pfkit:lan-pass"
${TCP_EGRESS_RULES}
${UDP_EGRESS_RULES}
EOF
)
fi

export EXT_IF ROUTER_IP DNS_OK LAN_NETS GOOGLE_ALLOWED_RENDERED EXTRA_HTTPS_TABLE BLACKLIST_TABLES BLACKLIST_RULES APPLE_LOCAL_RULES DOT_RULES QUIC_RULES MDNS_RULES UTUN_RULES EGRESS_RULES

rendered=$(perl -pe '
s/__APPLE_LOCAL_RULES__/$ENV{APPLE_LOCAL_RULES}/g;
s/__EXTRA_HTTPS_TABLE__/$ENV{EXTRA_HTTPS_TABLE}/g;
s/__BLACKLIST_TABLES__/$ENV{BLACKLIST_TABLES}/g;
s/__BLACKLIST_RULES__/$ENV{BLACKLIST_RULES}/g;
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
  echo "unresolved pf anchor template tokens:" >&2
  printf '  %s\n' $unresolved_tokens >&2
  exit 1
fi

printf "%s\n" "$rendered" > "$ANCHOR_DST"
chmod 644 "$ANCHOR_DST"

if ! grep -q '^anchor "pfkit"$' "$PFCONF" || ! grep -q '^load anchor "pfkit" from "/etc/pf\.anchors/pfkit\.anchor"' "$PFCONF"; then
  echo "pfkit is not wired into $PFCONF; run pfup first" >&2
  exit 1
fi

pfctl -q -a pfkit -nf "$ANCHOR_DST" >/dev/null
pfctl -q -a pfkit -f "$ANCHOR_DST" >/dev/null
pfctl -q -e >/dev/null 2>&1 || true

if [[ -n "${PFKIT_QUIET:-}" ]]; then
  exit 0
fi

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

printf '%s  %s\n' "$(paint '1;32' applied)" "pfkit rules loaded"
printf '  ext_if     : %s\n' "$EXT_IF"
printf '  dns_mode   : %s\n' "${DNS_MODE:-router}"
printf '  dns_ok     : %s\n' "$DNS_OK"
printf '  baseline   : %s\n' "$BASELINE_PROFILE"
printf '  tcp_ports  : %s\n' "${ALLOW_TCP_PORTS_RENDERED:-none}"
printf '  udp_ports  : %s\n' "${ALLOW_UDP_PORTS_RENDERED:-none}"
printf '  block_udp  : %s\n' "$BLOCK_ARBITRARY_UDP"
printf '  block_mdns : %s\n' "${BLOCK_MDNS:-0}"
printf '  block_quic : %s\n' "${BLOCK_QUIC:-1}"
printf '  block_utun : %s\n' "$BLOCK_UTUN"
