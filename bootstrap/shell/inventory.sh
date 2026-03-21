## dev

# dev-cmd: alias=comp name="Component Inventory" group=sys run=user legend=hide desc="Run the shared component inventory entrypoint"
comp() {
  local cmd="${1:-scan}"
  [[ $# -gt 0 ]] && shift

  case "$cmd" in
    scan)
      python3 "$HOME/dev/component-scan.sh" summary --color "$@"
      ;;
    legend)
      python3 "$HOME/dev/component-scan.sh" legend --color "$@"
      ;;
    records)
      python3 "$HOME/dev/component-scan.sh" records "$@"
      ;;
    validate)
      python3 "$HOME/dev/component-scan.sh" validate "$@"
      ;;
    dash)
      "$HOME/dev/devdash" "$@"
      ;;
    *)
      echo "comp commands: scan legend records validate dash"
      return 1
      ;;
  esac
}

# dev-cmd: alias=comp.scan name="Component Summary" group=sys run=user legend=hide desc="Show component summary"
alias comp.scan='comp scan'
# dev-cmd: alias=comp.legend name="Component Legend" group=sys run=user legend=hide desc="Show unified command legend"
alias comp.legend='comp legend'
# dev-cmd: alias=comp.records name="Component Records" group=sys run=user legend=hide desc="Emit component records"
alias comp.records='comp records'
# dev-cmd: alias=comp.validate name="Component Validation" group=sys run=user legend=hide desc="Validate component metadata and taxonomy"
alias comp.validate='comp validate'
# dev-cmd: alias=comp.dash name="Component Dashboard" group=sys run=user legend=hide desc="Open dev dashboard"
alias comp.dash='comp dash'

## dev

# dev-cmd: alias=dd name="Dev Dashboard" group=sys run=user legend=hide desc="Open dev dashboard"
alias dd='$HOME/dev/devdash'
# dev-cmd: alias=ds name=Summary group=sys run=user legend=hide desc="Show component summary"
alias ds='python3 "$HOME/dev/component-scan.sh" summary --color'
# dev-cmd: alias=dl name=Legend group=sys run=user legend=hide desc="Show unified command legend"
alias dl='python3 "$HOME/dev/component-scan.sh" legend --color'
# dev-cmd: alias=dr name=Records group=sys run=user legend=hide desc="Emit component records"
alias dr='python3 "$HOME/dev/component-scan.sh" records'
# dev-cmd: alias=dv name=Validation group=sys run=user legend=hide desc="Validate component metadata and taxonomy"
alias dv='python3 "$HOME/dev/component-scan.sh" validate'

## util

# dev-cmd: alias=l name=Legend group=sys run=user legend=hide desc="Show unified command legend"
l() {
  python3 "$HOME/dev/component-scan.sh" legend --color "$@"
}
