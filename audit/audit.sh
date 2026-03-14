#!/usr/bin/env bash
# @name: Audit Snapshot
# @desc: Quick macOS audit with network/process focus + lightweight delta
# @cmd: aud
# @keywords: audit macos network process
# @run: user
# @owner: firstparty

set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "audit.sh is macOS-only." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$ROOT_DIR"
OUT_JSON=""
RUN_ID=""
NO_COLOR=0
NET_STATE_FILE="$ROOT_DIR/state/net-last.json"
ZEEK_MODE=1
ZEEK_DIR=""
ZEEK_IPINFO=0

usage() {
  cat <<EOF
Usage:
  ./audit.sh
  ./audit.sh --out /path/to/output.json
  ./audit.sh --id shortword
  ./audit.sh --no-color
  ./audit.sh --zeek-dir /path/to/zlogs
  ./audit.sh --no-zeek
  ./audit.sh --zeek-ipinfo

Output:
  - Writes one JSON snapshot (default: audit-<word>.json)
  - Prints short summary to stdout
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT_JSON="${2:-}"
      shift 2
      ;;
    --id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --no-color)
      NO_COLOR=1
      shift
      ;;
    --zeek-dir)
      ZEEK_DIR="${2:-}"
      shift 2
      ;;
    --no-zeek)
      ZEEK_MODE=0
      shift
      ;;
    --zeek-ipinfo)
      ZEEK_IPINFO=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$RUN_ID" ]]; then
  words=(maple cedar pine ember slate river drift flint moss tide)
  idx=$((RANDOM % ${#words[@]}))
  RUN_ID="${words[$idx]}"
fi

if [[ -z "$OUT_JSON" ]]; then
  OUT_JSON="$OUT_DIR/audit-${RUN_ID}.json"
fi

mkdir -p "$(dirname "$OUT_JSON")" "$(dirname "$NET_STATE_FILE")"

if [[ "$NO_COLOR" -eq 1 ]]; then
  YEL=""; GRN=""; CYN=""; DIM=""; BOLD=""; RST=""
else
  tp() { tput "$@" 2>/dev/null || true; }
  YEL="$(tp setaf 3)"; GRN="$(tp setaf 2)"; CYN="$(tp setaf 6)"
  DIM="$(tp dim)"; BOLD="$(tp bold)"; RST="$(tp sgr0)"
fi

safe_cmd() {
  local out
  out="$("$@" 2>/dev/null || true)"
  printf "%s" "$out"
}

num_or_zero() {
  local v="${1//$'\n'/}"
  [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo 0
}

show_num() {
  local v="${1:-0}"
  [[ "$v" =~ ^[0-9]+$ ]] && printf "%s" "$v" || printf "n/a"
}

count_files() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo 0; return; }
  find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' '
}

resolve_zeek_log_dir() {
  local preferred="$1"
  local candidates=()

  if [[ -n "$preferred" ]]; then
    candidates+=("$preferred")
  fi
  if [[ -n "${ZEEK_LOG_DIR:-}" ]]; then
    candidates+=("$ZEEK_LOG_DIR")
  fi
  candidates+=("$ROOT_DIR/zlogs" "$ROOT_DIR/../zlogs" "$ROOT_DIR" "$HOME/zlogs")

  local d
  for d in "${candidates[@]}"; do
    [[ -d "$d" && -f "$d/conn.log" ]] && { printf "%s" "$d"; return; }
  done
  printf ""
}

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
HOST="$(hostname -s 2>/dev/null || hostname)"
MACOS_VERSION="$(safe_cmd sw_vers -productVersion)"
MACOS_BUILD="$(safe_cmd sw_vers -buildVersion)"
MODEL="$(safe_cmd sysctl -n hw.model)"
UPTIME_HUMAN="$(uptime 2>/dev/null | sed -E 's/^.*up ([^,]+),.*$/\1/' || true)"

# Security (high-level sheriff checks)
SIP_RAW="$(safe_cmd csrutil status)"
if echo "$SIP_RAW" | grep -qi "enabled"; then SIP_ENABLED=true; else SIP_ENABLED=false; fi

FW_CMD_STATE="unknown"
FW_PREF_STATE="unknown"
FW_RAW="$(safe_cmd /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate)"
if echo "$FW_RAW" | grep -Eqi 'enabled|state[[:space:]]*=[[:space:]]*1|state[[:space:]]*=[[:space:]]*2'; then
  FW_CMD_STATE=true
elif echo "$FW_RAW" | grep -Eqi 'disabled|state[[:space:]]*=[[:space:]]*0'; then
  FW_CMD_STATE=false
fi
ALF_STATE="$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || true)"
if [[ "$ALF_STATE" =~ ^[12]$ ]]; then
  FW_PREF_STATE=true
elif [[ "$ALF_STATE" == "0" ]]; then
  FW_PREF_STATE=false
fi
if [[ "$FW_CMD_STATE" == true || "$FW_PREF_STATE" == true ]]; then
  FIREWALL_ENABLED=true
elif [[ "$FW_CMD_STATE" == false && "$FW_PREF_STATE" == false ]]; then
  FIREWALL_ENABLED=false
else
  FIREWALL_ENABLED="unknown"
fi

GK_RAW="$(safe_cmd spctl --status)"
if echo "$GK_RAW" | grep -qi "assessments enabled"; then GATEKEEPER_ENABLED=true; else GATEKEEPER_ENABLED=false; fi

FV_RAW="$(safe_cmd fdesetup status)"
if echo "$FV_RAW" | grep -qi "filevault is on"; then FILEVAULT_ON=true; else FILEVAULT_ON=false; fi

# Network + process focus
DEFAULT_GW="$(route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}' || true)"
DEFAULT_IFACE="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}' || true)"
DNS_SERVERS_RAW="$(scutil --dns 2>/dev/null | awk '/nameserver\[[0-9]+\]/{print $3}' | awk '!seen[$0]++' | head -n 6 || true)"
LISTENING_TCP_COUNT="$(num_or_zero "$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{c++} END{print c+0}' || true)")"
ESTABLISHED_TCP_COUNT="$(num_or_zero "$(netstat -an 2>/dev/null | awk '/ESTABLISHED/{c++} END{print c+0}' || true)")"

ACTIVE_IFACES_RAW="$(ifconfig 2>/dev/null | awk '
  /^[a-z0-9]+: flags=/{iface=$1; sub(":","",iface)}
  /status: active/{active[iface]=1}
  /inet / && iface!="" && $2!="127.0.0.1"{
    if (ips[iface]=="") ips[iface]=$2; else ips[iface]=ips[iface]","$2
  }
  END{
    for(i in active){
      print i ":" (ips[i]!="" ? ips[i] : "-")
    }
  }' | sort || true)"

DHCP_PACKET="$(ipconfig getpacket "${DEFAULT_IFACE:-}" 2>/dev/null || true)"
DHCP_IP="$(printf "%s\n" "$DHCP_PACKET" | awk -F'= ' '/yiaddr/{gsub(";","",$2); print $2; exit}')"
DHCP_SERVER="$(printf "%s\n" "$DHCP_PACKET" | awk -F'= ' '/server_identifier/{gsub(";","",$2); print $2; exit}')"
DHCP_LEASE="$(printf "%s\n" "$DHCP_PACKET" | awk -F'= ' '/lease_time/{gsub(";","",$2); print $2; exit}')"

TOP_REMOTE_RAW="$(netstat -an 2>/dev/null | awk '/ESTABLISHED/ {print $5}' | sed 's/\.[0-9][0-9]*$//' | sort | uniq -c | sort -nr | head -n 5 | awk '{print $2 ":" $1}' || true)"
TOP_PROC_RAW="$(lsof -nP -i 2>/dev/null | awk 'NR>1 {c[$1]++} END {for (p in c) print p ":" c[p]}' | sort -t: -k2,2nr | head -n 5 || true)"
TOP_CPU_RAW="$(ps -axo user,comm,%cpu --sort=-%cpu 2>/dev/null | awk 'NR>1 && NR<=6 {print $1 ":" $2 ":" $3}' || true)"

# Other quick state
ROOT_USED_PCT="$(num_or_zero "$(df -h / | awk 'NR==2{gsub("%","",$5); print $5+0}' || true)")"
ROOT_FREE_HUMAN="$(df -h / | awk 'NR==2{print $4}' || echo "unknown")"
USER_LAUNCH_AGENTS="$(count_files "$HOME/Library/LaunchAgents")"
SYS_LAUNCH_AGENTS="$(count_files "/Library/LaunchAgents")"
SYS_LAUNCH_DAEMONS="$(count_files "/Library/LaunchDaemons")"
LOGIN_ITEMS_COUNT="$(num_or_zero "$(osascript -e 'tell application \"System Events\" to get count of every login item' 2>/dev/null || true)")"

ZEEK_ANALYZER="$ROOT_DIR/analysis/zeek_snapshot.py"
ZEEK_LOG_DIR_RESOLVED=""
ZEEK_REPORT_DIR="$ROOT_DIR/report/zeek"
ZEEK_REPORT_JSON="$ZEEK_REPORT_DIR/zeek-${RUN_ID}.json"
ZEEK_REPORT_BULLETS="$ZEEK_REPORT_DIR/zeek-${RUN_ID}.summary.txt"
ZEEK_REPORT_MD="$ZEEK_REPORT_DIR/zeek-${RUN_ID}.md"
ZEEK_REPORT_DOT="$ZEEK_REPORT_DIR/zeek-${RUN_ID}.graph.dot"
ZEEK_SUMMARY_HEADLINE=""

if [[ "$ZEEK_MODE" -eq 1 && -f "$ZEEK_ANALYZER" ]]; then
  ZEEK_LOG_DIR_RESOLVED="$(resolve_zeek_log_dir "$ZEEK_DIR")"
  if [[ -n "$ZEEK_LOG_DIR_RESOLVED" ]]; then
    mkdir -p "$ZEEK_REPORT_DIR"
    ZEEK_ENRICH_ARG=""
    [[ "$ZEEK_IPINFO" -eq 1 ]] && ZEEK_ENRICH_ARG="--enrich-ipinfo"
    if python3 "$ZEEK_ANALYZER" \
      --log-dir "$ZEEK_LOG_DIR_RESOLVED" \
      --out-json "$ZEEK_REPORT_JSON" \
      --out-bullets "$ZEEK_REPORT_BULLETS" \
      --out-md "$ZEEK_REPORT_MD" \
      --out-dot "$ZEEK_REPORT_DOT" \
      ${ZEEK_ENRICH_ARG:+$ZEEK_ENRICH_ARG} >/dev/null 2>&1; then
      if [[ -f "$ZEEK_REPORT_BULLETS" ]]; then
        ZEEK_SUMMARY_HEADLINE="$(head -n 1 "$ZEEK_REPORT_BULLETS" | sed 's/^- //')"
      fi
    fi
  fi
fi

anomalies_json='[]'
add_anomaly() {
  local sev="$1"; local cat="$2"; local msg="$3"
  anomalies_json="$(python3 - "$anomalies_json" "$sev" "$cat" "$msg" <<'PY'
import json, sys
arr = json.loads(sys.argv[1])
arr.append({"severity": sys.argv[2], "category": sys.argv[3], "message": sys.argv[4]})
print(json.dumps(arr))
PY
)"
}

[[ "$SIP_ENABLED" == true ]] || add_anomaly "high" "security" "SIP appears disabled."
[[ "$FIREWALL_ENABLED" == false ]] && add_anomaly "high" "security" "Application Firewall appears disabled."
[[ "$GATEKEEPER_ENABLED" == true ]] || add_anomaly "medium" "security" "Gatekeeper assessments are not enabled."
[[ -n "$DEFAULT_IFACE" ]] || add_anomaly "high" "network" "No default network interface detected."
[[ -n "$DEFAULT_GW" ]] || add_anomaly "medium" "network" "No default gateway detected."
(( ROOT_USED_PCT < 85 )) || add_anomaly "medium" "disk" "Root disk usage is ${ROOT_USED_PCT}%."

export TS HOST MACOS_VERSION MACOS_BUILD MODEL UPTIME_HUMAN RUN_ID NET_STATE_FILE
export SIP_ENABLED FIREWALL_ENABLED GATEKEEPER_ENABLED FILEVAULT_ON
export DEFAULT_GW DEFAULT_IFACE DNS_SERVERS_RAW LISTENING_TCP_COUNT ESTABLISHED_TCP_COUNT
export ACTIVE_IFACES_RAW DHCP_IP DHCP_SERVER DHCP_LEASE
export TOP_REMOTE_RAW TOP_PROC_RAW TOP_CPU_RAW
export ROOT_USED_PCT ROOT_FREE_HUMAN USER_LAUNCH_AGENTS SYS_LAUNCH_AGENTS SYS_LAUNCH_DAEMONS LOGIN_ITEMS_COUNT
export ZEEK_MODE ZEEK_DIR ZEEK_LOG_DIR_RESOLVED ZEEK_REPORT_DIR ZEEK_REPORT_JSON ZEEK_REPORT_BULLETS ZEEK_REPORT_MD ZEEK_REPORT_DOT ZEEK_SUMMARY_HEADLINE
export anomalies_json

JSON_DOC="$(python3 - <<'PY'
import json
import os
from pathlib import Path

def to_int(name):
    try:
        return int(str(os.environ.get(name, "0")).strip())
    except Exception:
        return 0

def to_bool(name):
    return str(os.environ.get(name, "")).strip().lower() == "true"

def lines(name):
    return [x.strip() for x in os.environ.get(name, "").splitlines() if x.strip()]

def iface_names(entries):
    out = []
    for e in entries:
        out.append(e.split(":", 1)[0])
    return out

state_file = Path(os.environ.get("NET_STATE_FILE", ""))
prev = {}
if state_file.exists():
    try:
        prev = json.loads(state_file.read_text())
    except Exception:
        prev = {}

cur_net = {
  "default_iface": os.environ.get("DEFAULT_IFACE", ""),
  "default_gateway": os.environ.get("DEFAULT_GW", ""),
  "active_ifaces": lines("ACTIVE_IFACES_RAW"),
  "dns_servers": lines("DNS_SERVERS_RAW"),
  "dhcp": {
    "iface": os.environ.get("DEFAULT_IFACE", ""),
    "ip": os.environ.get("DHCP_IP", ""),
    "server": os.environ.get("DHCP_SERVER", ""),
    "lease_time_s": os.environ.get("DHCP_LEASE", ""),
  },
  "conn": {
    "listening_tcp": to_int("LISTENING_TCP_COUNT"),
    "established_tcp": to_int("ESTABLISHED_TCP_COUNT"),
    "top_remote": lines("TOP_REMOTE_RAW"),
  },
}

prev_net = prev.get("net", {}) if isinstance(prev, dict) else {}
prev_dns = prev_net.get("dns_servers", []) if isinstance(prev_net, dict) else []
prev_ifaces = prev_net.get("active_ifaces", []) if isinstance(prev_net, dict) else []
prev_conn = prev_net.get("conn", {}) if isinstance(prev_net, dict) else {}

cur_iface_set = set(iface_names(cur_net["active_ifaces"]))
prev_iface_set = set(iface_names(prev_ifaces)) if isinstance(prev_ifaces, list) else set()

delta = {
  "baseline": not bool(prev_net),
  "default_gateway_changed": prev_net.get("default_gateway", "") != cur_net["default_gateway"],
  "dns_changed": prev_dns != cur_net["dns_servers"],
  "ifaces_added": sorted(cur_iface_set - prev_iface_set),
  "ifaces_removed": sorted(prev_iface_set - cur_iface_set),
  "listening_tcp_delta": cur_net["conn"]["listening_tcp"] - int(prev_conn.get("listening_tcp", 0) or 0),
  "established_tcp_delta": cur_net["conn"]["established_tcp"] - int(prev_conn.get("established_tcp", 0) or 0),
}
cur_net["delta"] = delta

zeek_obj = None
zeek_report = Path(os.environ.get("ZEEK_REPORT_JSON", ""))
if str(os.environ.get("ZEEK_MODE", "1")).strip() != "0" and zeek_report.exists():
    try:
        zeek_obj = json.loads(zeek_report.read_text())
    except Exception:
        zeek_obj = {"error": "failed_to_parse_zeek_report", "path": str(zeek_report)}

doc = {
  "cat": "audit",
  "id": os.environ.get("RUN_ID", ""),
  "ts": os.environ.get("TS", ""),
  "host": os.environ.get("HOST", ""),
  "sys": {
    "macos_version": os.environ.get("MACOS_VERSION", ""),
    "build": os.environ.get("MACOS_BUILD", ""),
    "model": os.environ.get("MODEL", ""),
    "uptime": os.environ.get("UPTIME_HUMAN", ""),
  },
  "sec": {
    "sip_enabled": to_bool("SIP_ENABLED"),
    "firewall_enabled": os.environ.get("FIREWALL_ENABLED", "unknown"),
    "gatekeeper_enabled": to_bool("GATEKEEPER_ENABLED"),
    "filevault_on": to_bool("FILEVAULT_ON"),
  },
  "net": cur_net,
  "proc": {
    "top_net_procs": lines("TOP_PROC_RAW"),
    "top_cpu": lines("TOP_CPU_RAW"),
  },
  "dsk": {
    "root_used_percent": to_int("ROOT_USED_PCT"),
    "root_free": os.environ.get("ROOT_FREE_HUMAN", "unknown"),
  },
  "per": {
    "user_launch_agents_count": to_int("USER_LAUNCH_AGENTS"),
    "system_launch_agents_count": to_int("SYS_LAUNCH_AGENTS"),
    "system_launch_daemons_count": to_int("SYS_LAUNCH_DAEMONS"),
    "login_items_count": to_int("LOGIN_ITEMS_COUNT"),
  },
  "findings": json.loads(os.environ.get("anomalies_json", "[]")),
}

if zeek_obj is not None:
  doc["zeek"] = zeek_obj

state_file.parent.mkdir(parents=True, exist_ok=True)
state_file.write_text(json.dumps({"ts": doc["ts"], "net": doc["net"]}, indent=2) + "\n")
print(json.dumps(doc, indent=2))
PY
)"

printf "%s\n" "$JSON_DOC" > "$OUT_JSON"

anom_count="$(python3 - "$anomalies_json" <<'PY'
import json, sys
print(len(json.loads(sys.argv[1])))
PY
)"

sec_status="OK"; sec_color="$GRN"
if [[ "$SIP_ENABLED" != true || "$FIREWALL_ENABLED" == false || "$GATEKEEPER_ENABLED" != true ]]; then
  sec_status="WARN"; sec_color="$YEL"
fi

net_status="OK"; net_color="$GRN"
if [[ -z "$DEFAULT_IFACE" || -z "$DEFAULT_GW" ]]; then
  net_status="WARN"; net_color="$YEL"
fi

dns_show="$(printf "%s\n" "$DNS_SERVERS_RAW" | paste -sd ',' -)"
ifaces_show="$(printf "%s\n" "$ACTIVE_IFACES_RAW" | head -n 3 | paste -sd ';' -)"
top_proc_show="$(printf "%s\n" "$TOP_PROC_RAW" | head -n 3 | paste -sd ',' -)"
delta_show="$(python3 - "$OUT_JSON" <<'PY'
import json, sys
obj = json.load(open(sys.argv[1]))
d = obj.get("net", {}).get("delta", {})
if d.get("baseline"):
    print("baseline")
else:
    print(f"dns_changed={d.get('dns_changed')} est_delta={d.get('established_tcp_delta')} listen_delta={d.get('listening_tcp_delta')} if_add={len(d.get('ifaces_added', []))} if_rm={len(d.get('ifaces_removed', []))}")
PY
)"

printf "%sQuick macOS Assessment%s\n" "$BOLD$CYN" "$RST"
printf "%srun=%s  ts=%s%s\n" "$DIM" "$RUN_ID" "$TS" "$RST"
printf "%s%s%s  macOS %s (%s)  model=%s\n" "$sec_color" "$sec_status" "$RST" "$MACOS_VERSION" "$MACOS_BUILD" "$MODEL"
printf "%s%s%s  security  sip=%s firewall=%s gatekeeper=%s filevault=%s\n" "$sec_color" "$sec_status" "$RST" "$SIP_ENABLED" "$FIREWALL_ENABLED" "$GATEKEEPER_ENABLED" "$FILEVAULT_ON"
printf "%s%s%s  network   if=%s gw=%s listen=%s established=%s\n" "$net_color" "$net_status" "$RST" "${DEFAULT_IFACE:-unknown}" "${DEFAULT_GW:-unknown}" "$(show_num "$LISTENING_TCP_COUNT")" "$(show_num "$ESTABLISHED_TCP_COUNT")"
printf "%sINFO%s  dns=%s\n" "$DIM" "$RST" "${dns_show:-unknown}"
printf "%sINFO%s  ifaces=%s\n" "$DIM" "$RST" "${ifaces_show:-unknown}"
printf "%sINFO%s  dhcp iface=%s ip=%s server=%s lease=%s\n" "$DIM" "$RST" "${DEFAULT_IFACE:-unknown}" "${DHCP_IP:-}" "${DHCP_SERVER:-}" "${DHCP_LEASE:-}"
printf "%sINFO%s  proc(top-net)=%s\n" "$DIM" "$RST" "${top_proc_show:-none}"
printf "%sINFO%s  net-delta=%s\n" "$DIM" "$RST" "$delta_show"
if [[ -f "$ZEEK_REPORT_JSON" ]]; then
  printf "%sINFO%s  zeek=%s (%s)\n" "$DIM" "$RST" "${ZEEK_LOG_DIR_RESOLVED:-unknown}" "${ZEEK_SUMMARY_HEADLINE:-snapshot ready}"
else
  [[ "$ZEEK_MODE" -eq 1 ]] && printf "%sINFO%s  zeek=not found (use --zeek-dir or place logs in audit/zlogs)\n" "$DIM" "$RST"
fi
printf "%sINFO%s  disk root_used=%s%% free=%s  persistence ua=%s sa=%s sd=%s li=%s\n" "$DIM" "$RST" "$(show_num "$ROOT_USED_PCT")" "$ROOT_FREE_HUMAN" "$(show_num "$USER_LAUNCH_AGENTS")" "$(show_num "$SYS_LAUNCH_AGENTS")" "$(show_num "$SYS_LAUNCH_DAEMONS")" "$(show_num "$LOGIN_ITEMS_COUNT")"

if [[ "$anom_count" -gt 0 ]]; then
  printf "%sFindings (%s)%s\n" "$BOLD$YEL" "$anom_count" "$RST"
  python3 - "$anomalies_json" <<'PY'
import json, sys
for a in json.loads(sys.argv[1])[:10]:
    print(f"- [{a['severity']}] {a['category']}: {a['message']}")
PY
else
  printf "%sFindings%s\n- none\n" "$BOLD$GRN" "$RST"
fi

printf "%sJSON:%s %s\n" "$DIM" "$RST" "$OUT_JSON"
if [[ -f "$ZEEK_REPORT_JSON" ]]; then
  printf "%sZEEK:%s %s\n" "$DIM" "$RST" "$ZEEK_REPORT_JSON"
  printf "%sZEEK:%s %s\n" "$DIM" "$RST" "$ZEEK_REPORT_BULLETS"
  printf "%sZEEK:%s %s\n" "$DIM" "$RST" "$ZEEK_REPORT_MD"
  printf "%sZEEK:%s %s\n" "$DIM" "$RST" "$ZEEK_REPORT_DOT"
fi
