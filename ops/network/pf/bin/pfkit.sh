#!/usr/bin/env bash
# Internal dispatcher for PFKit start, stop, update, and logs commands.
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
REPO_ROOT="$(cd "$ROOT_DIR/../../.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
ANCHOR_DST="/etc/pf.anchors/pfkit.anchor"

repo_owner() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
    return
  fi
  stat -f '%Su' "$ROOT_DIR" 2>/dev/null || id -un
}

repair_repo_file_perms() {
  local path="$1" owner
  owner="$(repo_owner)"
  chown "$owner":staff "$path" 2>/dev/null || true
  chmod 644 "$path"
}

ensure_repo_files() {
  local anchor_template="$ROOT_DIR/anchors/pfkit.anchor"
  local env_file="$ROOT_DIR/config/pfkit.env"
  local owner

  owner="$(repo_owner)"
  mkdir -p "$ROOT_DIR/anchors" "$ROOT_DIR/config"
  chown "$owner":staff "$ROOT_DIR/anchors" "$ROOT_DIR/config" 2>/dev/null || true

  if [[ ! -f "$anchor_template" ]]; then
    cat > "$anchor_template" <<'EOF'
# pfkit.anchor

# Anchor-local skip is not reliable on macOS. Pass loopback early so local
# service chatter does not fall into the default block logger.
pass quick on lo0 all label "pfkit:loopback-pass"
__APPLE_LOCAL_RULES__

table <dns_ok> persist { __DNS_OK__ }
table <lan_nets> persist { __LAN_NETS__ }
table <google_endpoints> persist { __GOOGLE_ALLOWED__ }
__EXTRA_HTTPS_TABLE__
__BLACKLIST_TABLES__

# ------------------------------
# IP / CIDR blacklist layer
# ------------------------------
__BLACKLIST_RULES__

# ------------------------------
# DNS enforcement
# ------------------------------

# Allow DNS only to approved resolvers on the primary interface
pass out log (all) quick on __EXT_IF__ inet proto { udp tcp } to <dns_ok> port 53 keep state label "pfkit:dns-pass"

# Block all other IPv4 DNS
block return log quick inet proto { udp tcp } to any port 53 label "pfkit:dns-block"

# ------------------------------
# Block DNS-over-TLS / DoQ
# ------------------------------
__DOT_RULES__

# ------------------------------
# Block QUIC / HTTP3
# ------------------------------
__QUIC_RULES__

# ------------------------------
# Block multicast DNS noise
# ------------------------------
__MDNS_RULES__

# ------------------------------
# Optional utun kill-switch layer
# ------------------------------
__UTUN_RULES__

# ------------------------------
# Main egress policy
# ------------------------------
__EGRESS_RULES__

# ------------------------------
# Default deny
# ------------------------------
block log all label "pfkit:default-block"
EOF
    repair_repo_file_perms "$anchor_template"
    echo ">> Restored missing pfkit anchor template: $anchor_template"
  fi

  if [[ ! -f "$env_file" ]]; then
    cat > "$env_file" <<'EOF'
# pfkit.env
# Configure, then: sudo pfkit update

# External interface (optional). Leave empty to auto-detect.
EXT_IF=""

# DNS policy:
# - router: only default gateway may receive DNS
# - direct: only DNS_ALLOWED may receive DNS
DNS_MODE=router
DNS_ALLOWED=""

# RFC1918 LAN ranges
ALLOW_LAN_CIDRS="192.168.0.0/16 10.0.0.0/8 172.16.0.0/12"

# Intent baseline for this profile.
BASELINE_PROFILE="default"

# Tight normal-mode egress:
# - TCP is limited to this port set
# - UDP is blocked except DNS plus ALLOW_UDP_PORTS below
ALLOW_TCP_PORTS="22 80 443"
ALLOW_UDP_PORTS=""
BLOCK_ARBITRARY_UDP=1

# Bonjour / AirDrop / AirPrint / multicast discovery.
BLOCK_MDNS=1

# Block Apple-managed peer / continuity interfaces by default.
BLOCK_APPLE_P2P=1

# utun* are system-managed tunnels (VPN / NetworkExtension).
BLOCK_UTUN=1

# Block DNS-over-TLS / DoQ egress on 853
BLOCK_DOT=1

# Block QUIC / HTTP3 so browsers fall back to TCP/443
BLOCK_QUIC=1

# Google endpoint mode:
# - hosts: resolve a tight Google sign-in hostname list at apply time
# - manual: use GOOGLE_ALLOWED IPv4 CIDRs directly
GOOGLE_ENDPOINT_MODE=hosts
GOOGLE_ALLOWED=""
GOOGLE_ALLOWED_HOSTS="accounts.google.com ssl.gstatic.com www.gstatic.com"

# Narrow non-Google HTTPS exceptions that still need to work.
EXTRA_HTTPS_ALLOWED=""
EXTRA_HTTPS_ALLOWED_HOSTS=""

# Space-delimited IPs and/or CIDRs to block before the normal policy.
BLACKLIST_IN_CIDRS=""
BLACKLIST_OUT_CIDRS=""

# Back-compat alias
GGC_ALLOWED=""

# 0 = normal web browsing allowed
# 1 = HTTPS only to Google-owned endpoints
GOOGLE_ONLY_MODE=0
EOF
    repair_repo_file_perms "$env_file"
    echo ">> Restored missing pfkit config: $env_file"
  fi
}

usage() {
  cat <<'EOF'
usage: pfkit <command>

Commands:
  start   → update rules, enable PF, and start block logging
  stop    → stop block logging, unload PFKit rules, and disable PF globally
  status  → show whether PFKit is running
  update  → repair files/wiring, render config, and load PFKit rules
  logs    → manage or inspect retained block logs

Logs:
  pfkit logs [report|tail|cat|path|clear|start|stop] [lines]

EOF
}

ensure_wired() {
  [[ -f /etc/pf.conf ]] || return 1
  grep -q '^load anchor "pfkit" from "/etc/pf\.anchors/pfkit\.anchor"' /etc/pf.conf &&
    grep -q '^anchor "pfkit"$' /etc/pf.conf
}

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

status_pfkit() {
  local status_line pfkit_rules logger_state logger_pid pf_state pfkit_state pflog_state overall
  status_line="$(pfctl -q -s info 2>/dev/null | sed -n '/^Status:/p' || true)"
  pfkit_rules="$(pfctl -q -a pfkit -sr 2>/dev/null || true)"
  pf_state="off"
  pfkit_state="off"
  pflog_state="missing"
  logger_state="stopped"
  logger_pid=""

  [[ "$status_line" == *"Enabled"* ]] && pf_state="on"
  [[ -n "$pfkit_rules" ]] && pfkit_state="on"
  if ifconfig pflog0 >/dev/null 2>&1; then
    pflog_state="present"
  fi

  local log_dir="${DEV_LOG_ROOT:-$REPO_ROOT/logs}/pfkit"
  if [[ -f "$log_dir/blocks.pid" ]]; then
    logger_pid="$(cat "$log_dir/blocks.pid" 2>/dev/null || true)"
    if [[ -n "$logger_pid" ]] && kill -0 "$logger_pid" 2>/dev/null; then
      logger_state="running"
    fi
  fi

  overall="stopped"
  if [[ "$pf_state" == "on" && "$pfkit_state" == "on" && "$logger_state" == "running" ]]; then
    overall="running"
  elif [[ "$pf_state" == "on" && "$pfkit_state" == "on" ]]; then
    overall="partial"
  fi

  if [[ "$overall" == "running" ]]; then
    printf '%s  %s\n' "$(paint '1;32' RUNNING)" "PFKit is active"
  elif [[ "$overall" == "partial" ]]; then
    printf '%s  %s\n' "$(paint '1;33' PARTIAL)" "PFKit rules are loaded, logger is not running"
  else
    printf '%s  %s\n' "$(paint '1;31' STOPPED)" "PFKit is not fully active"
  fi

  printf '  pf      : %s\n' "$pf_state"
  printf '  anchor  : %s\n' "$pfkit_state"
  printf '  logger  : %s%s\n' "$logger_state" "${logger_pid:+ pid=$logger_pid}"
  printf '  pflog0  : %s\n' "$pflog_state"
  printf '  log     : %s\n' "$log_dir/blocks.log"
}

update_pfkit() {
  ensure_repo_files
  if ! ensure_wired; then
    bash "$BIN_DIR/pfkit-install.sh"
  fi
  bash "$BIN_DIR/pfkit-apply.sh"
}

start_pfkit() {
  update_pfkit
  bash "$BIN_DIR/pfkit-log.sh" start
}

stop_pfkit() {
  bash "$BIN_DIR/pfkit-log.sh" stop

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

logs_pfkit() {
  local log_cmd="${1:-report}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  case "$log_cmd" in
    report|tail|cat|path|clear|start|stop)
      bash "$BIN_DIR/pfkit-log.sh" "$log_cmd" "$@"
      ;;
    *)
      bash "$BIN_DIR/pfkit-log.sh" "$log_cmd" "$@"
      ;;
  esac
}

cmd="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  start)
    start_pfkit
    ;;
  status)
    status_pfkit
    ;;
  update)
    update_pfkit
    ;;
  logs)
    logs_pfkit "$@"
    ;;
  stop)
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
