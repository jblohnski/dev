## audit

export AUDIT_DIR="$HOME/dev/audit"
export ZEEK_LOG_DIR="${ZEEK_LOG_DIR:-$HOME/zlogs}"

# @component
# @name: Audit
# @desc: Run the main audit entrypoint
# @cmd: a
# @keywords: audit macos snapshot
alias a='builtin cd "$AUDIT_DIR" && ./audit.sh'

# @name: Zeek Workflow
# @desc: Run Zeek capture and report workflow subcommands
# @cmd: az
# @keywords: audit zeek workflow
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

# @name: Zeek Run
# @desc: Run Zeek report generation
# @cmd: az.run
# @keywords: audit zeek report
alias az.run='az run'
# @name: Zeek Start
# @desc: Start background Zeek capture
# @cmd: az.start
# @keywords: audit zeek capture
alias az.start='az start'
# @name: Zeek Stop
# @desc: Stop background Zeek capture
# @cmd: az.stop
# @keywords: audit zeek capture
alias az.stop='az stop'
# @name: Zeek Status
# @desc: Show background Zeek capture status
# @cmd: az.stat
# @keywords: audit zeek status
alias az.stat='az stat'
# @name: Zeek Merge
# @desc: Merge stray local Zeek logs into $ZEEK_LOG_DIR
# @cmd: az.merge
# @keywords: audit zeek sync
alias az.merge='az merge'
# @name: Zeek UID
# @desc: Run Zeek report by uid
# @cmd: az.uid
# @keywords: audit zeek uid
alias az.uid='az uid'
# @name: Zeek Tuple
# @desc: Run Zeek report by tuple
# @cmd: az.tuple
# @keywords: audit zeek tuple
alias az.tuple='az tuple'

# @name: Audit Report
# @desc: Print latest Zeek markdown report path
# @cmd: arpt
# @keywords: audit zeek report
arpt() {
  local f
  f="$(command ls -1t "$AUDIT_DIR"/report/zeek/zeek-*.md 2>/dev/null | head -n 1 || true)"
  [[ -n "$f" ]] && print "$f" || print "no zeek markdown report found"
}

# @name: Audit Zip
# @desc: Zip up audit project code only
# @cmd: azip
# @keywords: audit archive sources
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
