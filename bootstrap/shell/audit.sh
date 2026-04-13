## audit

export AUDIT_DIR="$HOME/dev/audit"
export ZEEK_LOG_DIR="${ZEEK_LOG_DIR:-${DEV_LOG_ROOT:-$HOME/dev/logs}/zeek}"

# dev-cmd: alias=a name=Audit group=audit run=user desc="Run the main audit entrypoint"
a() {
  "$AUDIT_DIR/audit.sh" "$@"
}

# dev-cmd: alias=az name="Zeek Workflow" group=audit run=user desc="Run Zeek capture and report workflow subcommands"
az() {
  local cmd="${1:-run}"
  [[ $# -gt 0 ]] && shift

  case "$cmd" in
    run)
      "$AUDIT_DIR/zeek-audit.sh" "$ZEEK_LOG_DIR" "$@"
      ;;
    start)
      local iface="${1:-${ZEEK_CAPTURE_IFACE:-en0}}"
      [[ $# -gt 0 ]] && shift
      "$AUDIT_DIR/zeek-capture.sh" start "$iface" "$@"
      ;;
    stop)
      "$AUDIT_DIR/zeek-capture.sh" stop
      ;;
    stat|status)
      "$AUDIT_DIR/zeek-capture.sh" status
      ;;
    merge)
      "$AUDIT_DIR/zeek-logsync.sh"
      ;;
    uid)
      local uid="${1:?uid required}"
      "$AUDIT_DIR/zeek-audit.sh" "$ZEEK_LOG_DIR" "uid-$(date +%Y%m%d-%H%M%S)" -- --uid "$uid"
      ;;
    tuple)
      local src="${1:?src_ip required}"
      local dst="${2:?dst_ip required}"
      local port="${3:?dst_port required}"
      local ts="${4:?timestamp required}"
      local run="${5:-tuple-$(date +%Y%m%d-%H%M%S)}"
      "$AUDIT_DIR/zeek-audit.sh" "$ZEEK_LOG_DIR" "$run" -- \
        --src-ip "$src" --dst-ip "$dst" --dst-port "$port" --ts "$ts"
      ;;
    *)
      echo "az commands: run start stop stat merge uid tuple"
      return 1
      ;;
  esac
}

alias az.run='az run'
alias az.start='az start'
alias az.stop='az stop'
alias az.stat='az stat'
alias az.merge='az merge'
alias az.uid='az uid'
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

# @component: ops
alias logsum.live='"$DEV_ROOT/ops/diagnostics/logsum.sh" --last 15m --top 3'
alias logsum.wide='"$DEV_ROOT/ops/diagnostics/logsum.sh" --last 1h --top 5'
alias logsum.counts='"$DEV_ROOT/ops/diagnostics/logsum.sh" --last 30m --top 5 --counts'
