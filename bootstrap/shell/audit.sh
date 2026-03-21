## audit

export AUDIT_DIR="$HOME/dev/audit"
export ZEEK_LOG_DIR="${ZEEK_LOG_DIR:-$HOME/zlogs}"

# dev-cmd: alias=a name=Audit group=audit run=user desc="Run the main audit entrypoint"
alias a='builtin cd "$AUDIT_DIR" && ./audit.sh'

# dev-cmd: alias=az name="Zeek Workflow" group=audit run=user desc="Run Zeek capture and report workflow subcommands"
az() {
  local cmd="${1:-run}"
  [[ $# -gt 0 ]] && shift

  case "$cmd" in
    run)
      builtin cd "$AUDIT_DIR" || return
      ./zeek-audit.sh "$ZEEK_LOG_DIR" "$@"
      ;;
    start)
      local iface="${1:-${ZEEK_CAPTURE_IFACE:-en0}}"
      [[ $# -gt 0 ]] && shift
      builtin cd "$AUDIT_DIR" || return
      ./zeek-capture.sh start "$iface" "$@"
      ;;
    stop)
      builtin cd "$AUDIT_DIR" || return
      ./zeek-capture.sh stop
      ;;
    stat|status)
      builtin cd "$AUDIT_DIR" || return
      ./zeek-capture.sh status
      ;;
    merge)
      builtin cd "$AUDIT_DIR" || return
      ./zeek-logsync.sh
      ;;
    uid)
      local uid="${1:?uid required}"
      builtin cd "$AUDIT_DIR" || return
      ./zeek-audit.sh "$ZEEK_LOG_DIR" "uid-$(date +%Y%m%d-%H%M%S)" -- --uid "$uid"
      ;;
    tuple)
      local src="${1:?src_ip required}"
      local dst="${2:?dst_ip required}"
      local port="${3:?dst_port required}"
      local ts="${4:?timestamp required}"
      local run="${5:-tuple-$(date +%Y%m%d-%H%M%S)}"
      builtin cd "$AUDIT_DIR" || return
      ./zeek-audit.sh "$ZEEK_LOG_DIR" "$run" -- \
        --src-ip "$src" --dst-ip "$dst" --dst-port "$port" --ts "$ts"
      ;;
    *)
      echo "az commands: run start stop stat merge uid tuple"
      return 1
      ;;
  esac
}

# dev-cmd: alias=az.run name="Zeek Run" group=audit run=user desc="Run Zeek report generation"
alias az.run='az run'
# dev-cmd: alias=az.start name="Zeek Start" group=audit run=user desc="Start background Zeek capture"
alias az.start='az start'
# dev-cmd: alias=az.stop name="Zeek Stop" group=audit run=user desc="Stop background Zeek capture"
alias az.stop='az stop'
# dev-cmd: alias=az.stat name="Zeek Status" group=audit run=user desc="Show background Zeek capture status"
alias az.stat='az stat'
# dev-cmd: alias=az.merge name="Zeek Merge" group=audit run=user desc="Merge stray local Zeek logs into $ZEEK_LOG_DIR"
alias az.merge='az merge'
# dev-cmd: alias=az.uid name="Zeek UID" group=audit run=user desc="Run Zeek report by uid"
alias az.uid='az uid'
# dev-cmd: alias=az.tuple name="Zeek Tuple" group=audit run=user desc="Run Zeek report by tuple"
alias az.tuple='az tuple'

# dev-cmd: alias=arpt name="Audit Report" group=audit run=user desc="Print latest Zeek markdown report path"
arpt() {
  local f
  f="$(command ls -1t "$AUDIT_DIR"/report/zeek/zeek-*.md 2>/dev/null | head -n 1 || true)"
  [[ -n "$f" ]] && print "$f" || print "no zeek markdown report found"
}

# dev-cmd: alias=azip name="Audit Zip" group=audit run=user desc="Zip up audit project code only"
azip() {
  zip -r audit.zip audit \
    -x "audit/.git/*" \
    -x "audit/archives/*" \
    -x "audit/__pycache__/*" \
    -x "audit/*/__pycache__/*" \
    -x "audit/*.pyc" \
    -x "audit/*.pyo" \
    -x "audit/baseline/*" \
    -x "audit/current/*" \
    -x "audit/report/*" \
    -x "audit/state/*" \
    -x "audit/*.log" \
    -x "audit/*.pcap*" \
    -x "audit/.DS_Store" \
    -x "audit/*/.DS_Store" \
    -x "audit/._*"
}
