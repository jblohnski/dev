## audit

export AUDIT_DIR="${AUDIT_DIR:-$HOME/dev/audit}"
export ZEEK_LOG_DIR="${ZEEK_LOG_DIR:-${DEV_LOG_ROOT:-$HOME/dev/logs}/zeek}"

# dev-cmd: alias=audit name="Audit Scan" group=audit run=user desc="Run the system audit and emit the core trust-oriented summary"
audit() {
  "$AUDIT_DIR/audit.sh" "$@"
}

# dev-cmd: alias=audit.monitor name="Audit Monitor" group=audit run=user desc="Manage audit logging capture, monitor traces, and focused deep-dive helpers"
alias audit.monitor='audit_monitor'
audit_monitor() {
  local cmd="${1:-status}"
  [[ $# -gt 0 ]] && shift

  case "$cmd" in
    start)
      local iface="${1:-${ZEEK_CAPTURE_IFACE:-en0}}"
      if [[ $# -gt 0 && "${1:-}" != "--" ]]; then
        shift
      fi
      "$AUDIT_DIR/zeek-capture.sh" start "$iface" "$@"
      ;;
    stop)
      "$AUDIT_DIR/zeek-capture.sh" stop
      ;;
    status|stat)
      "$AUDIT_DIR/zeek-capture.sh" status
      ;;
    merge)
      "$AUDIT_DIR/zeek-logsync.sh" "$@"
      ;;
    logs)
      "$DEV_ROOT/ops/diagnostics/logsum.sh" "$@"
      ;;
    ui|windowserver)
      "$DEV_ROOT/ops/diagnostics/wstrace.sh" "$@"
      ;;
    netshot)
      "$AUDIT_DIR/netshot/netshot.sh" "$@"
      ;;
    prefs-watch)
      "$AUDIT_DIR/macsm.sh" "$@"
      ;;
    prefs-report)
      "$AUDIT_DIR/macsm-anlyz.sh" "$@"
      ;;
    help|-h|--help|"")
      cat <<'EOF'
Usage:
  audit.monitor status
  audit.monitor start [iface] [-- zeek args...]
  audit.monitor stop
  audit.monitor merge [source_dir] [target_dir]
  audit.monitor logs [logsum args...]
  audit.monitor ui [range]
  audit.monitor netshot [seconds]
  audit.monitor prefs-watch
  audit.monitor prefs-report <run_dir>
EOF
      ;;
    *)
      echo "audit.monitor commands: start stop status merge logs ui netshot prefs-watch prefs-report"
      return 1
      ;;
  esac
}

audit_latest_json() {
  setopt local_options null_glob
  local -a matches
  matches=("$AUDIT_DIR"/audit-*.json)
  (( ${#matches[@]} )) || return 0
  command ls -1t -- "${matches[@]}" 2>/dev/null | head -n 1 || true
}

audit_json_artifact() {
  local key="$1"
  local audit_json
  audit_json="$(audit_latest_json)"
  [[ -f "$audit_json" ]] || return 0
  python3 - "$audit_json" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    doc = json.load(handle)

print(doc.get("artifacts", {}).get(sys.argv[2], ""))
PY
}

audit_latest_zeek_json() {
  local audit_json
  audit_json="$(audit_latest_json)"
  if [[ -f "$audit_json" ]]; then
    audit_json_artifact zeek_json
    return 0
  fi
  setopt local_options null_glob
  local -a matches
  matches=("$AUDIT_DIR"/report/zeek/zeek-*.json)
  (( ${#matches[@]} )) || return 0
  command ls -1t -- "${matches[@]}" 2>/dev/null | head -n 1 || true
}

audit_latest_zeek_bullets() {
  local audit_json
  audit_json="$(audit_latest_json)"
  if [[ -f "$audit_json" ]]; then
    audit_json_artifact zeek_bullets
    return 0
  fi
  setopt local_options null_glob
  local -a matches
  matches=("$AUDIT_DIR"/report/zeek/zeek-*.summary.txt)
  (( ${#matches[@]} )) || return 0
  command ls -1t -- "${matches[@]}" 2>/dev/null | head -n 1 || true
}

audit_latest_zeek_md() {
  local audit_json
  audit_json="$(audit_latest_json)"
  if [[ -f "$audit_json" ]]; then
    audit_json_artifact zeek_markdown
    return 0
  fi
  setopt local_options null_glob
  local -a matches
  matches=("$AUDIT_DIR"/report/zeek/zeek-*.md)
  (( ${#matches[@]} )) || return 0
  command ls -1t -- "${matches[@]}" 2>/dev/null | head -n 1 || true
}

audit_latest_trust_summary() {
  local audit_json
  audit_json="$(audit_latest_json)"
  if [[ -f "$audit_json" ]]; then
    audit_json_artifact trust_summary
    return 0
  fi
  setopt local_options null_glob
  local -a matches
  matches=("$AUDIT_DIR"/report/trust/trust-*/trust_summary.txt)
  (( ${#matches[@]} )) || return 0
  command ls -1t -- "${matches[@]}" 2>/dev/null | head -n 1 || true
}

audit_print_paths() {
  local audit_json zeek_json zeek_bullets zeek_md trust_summary
  audit_json="$(audit_latest_json)"
  zeek_json="$(audit_latest_zeek_json)"
  zeek_bullets="$(audit_latest_zeek_bullets)"
  zeek_md="$(audit_latest_zeek_md)"
  trust_summary="$(audit_latest_trust_summary)"

  print "audit_json=${audit_json:-missing}"
  print "zeek_json=${zeek_json:-missing}"
  print "zeek_bullets=${zeek_bullets:-missing}"
  print "zeek_markdown=${zeek_md:-missing}"
  print "trust_summary=${trust_summary:-missing}"
}

# dev-cmd: alias=audit.status name="Audit Status" group=audit run=user desc="Show audit subsystem state, latest artifacts, and trust/report readiness"
alias audit.status='audit_status'
audit_status() {
  local audit_json
  audit_json="$(audit_latest_json)"

  print "== audit monitor =="
  "$AUDIT_DIR/zeek-capture.sh" status 2>/dev/null || print "status=unavailable"
  print ""

  print "== latest artifacts =="
  audit_print_paths

  if [[ -f "$audit_json" ]]; then
    print ""
    print "== latest audit snapshot =="
    python3 - "$audit_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    doc = json.load(handle)

trust = doc.get("trust", {})
sec = doc.get("sec", {})
net = doc.get("net", {})
delta = net.get("delta", {})

print(f"id={doc.get('id', '')}")
print(f"ts={doc.get('ts', '')}")
print(f"findings={len(doc.get('findings', []))}")
print(
    "security="
    f"sip={sec.get('sip_enabled')} firewall={sec.get('firewall_enabled')} "
    f"gatekeeper={sec.get('gatekeeper_enabled')} filevault={sec.get('filevault_on')}"
)
print(
    "network="
    f"iface={net.get('default_iface', '') or 'unknown'} "
    f"gw={net.get('default_gateway', '') or 'unknown'} "
    f"baseline={delta.get('baseline')}"
)
print(
    "trust="
    f"status={trust.get('status', 'unavailable')} "
    f"issues={trust.get('issues', 0)} "
    f"summary={trust.get('summary', '')}"
)
PY
  fi
}

# dev-cmd: alias=audit.report name="Audit Report" group=audit run=user desc="Show the latest audit output, trust summary, and Zeek report material"
alias audit.report='audit_report'
audit_report() {
  local cmd="${1:-show}"
  [[ $# -gt 0 ]] && shift

  case "$cmd" in
    show|latest)
      local audit_json zeek_bullets zeek_md trust_summary
      audit_json="$(audit_latest_json)"
      zeek_bullets="$(audit_latest_zeek_bullets)"
      zeek_md="$(audit_latest_zeek_md)"
      trust_summary="$(audit_latest_trust_summary)"

      audit_print_paths

      if [[ -f "$audit_json" ]]; then
        print ""
        print "== audit summary =="
        python3 - "$audit_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    doc = json.load(handle)

print(f"run={doc.get('id', '')} ts={doc.get('ts', '')}")
for finding in doc.get("findings", [])[:10]:
    print(f"- [{finding.get('severity', 'info')}] {finding.get('category', 'general')}: {finding.get('message', '')}")
if not doc.get("findings"):
    print("- no findings")
trust = doc.get("trust", {})
print(f"trust: {trust.get('status', 'unavailable')} issues={trust.get('issues', 0)} {trust.get('summary', '')}")
PY
      fi

      if [[ -f "$trust_summary" ]]; then
        print ""
        print "== trust summary =="
        sed -n '1,20p' "$trust_summary"
      fi

      if [[ -f "$zeek_bullets" ]]; then
        print ""
        print "== zeek summary =="
        sed -n '1,20p' "$zeek_bullets"
      elif [[ -f "$zeek_md" ]]; then
        print ""
        print "zeek_markdown=$zeek_md"
      fi
      ;;
    paths|path)
      audit_print_paths
      ;;
    refresh)
      local run_id
      run_id="${1:-$(date +%Y%m%d-%H%M%S)}"
      if [[ $# -gt 0 && "${1:-}" != "--" ]]; then
        shift
      fi
      "$AUDIT_DIR/zeek-audit.sh" "$ZEEK_LOG_DIR" "$run_id" "$@"
      ;;
    help|-h|--help|"")
      cat <<'EOF'
Usage:
  audit.report
  audit.report show
  audit.report paths
  audit.report refresh [run_id] [-- analyzer args...]
EOF
      ;;
    *)
      echo "audit.report commands: show paths refresh"
      return 1
      ;;
  esac
}

a() {
  audit "$@"
}

az() {
  audit_monitor "$@"
}

arpt() {
  audit_report paths
}
