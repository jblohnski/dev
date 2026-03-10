## dev

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

# comp.scan: show component summary
alias comp.scan='comp scan'
# comp.legend: show unified command legend
alias comp.legend='comp legend'
# comp.records: emit component records
alias comp.records='comp records'
# comp.validate: validate component metadata and taxonomy
alias comp.validate='comp validate'
# comp.dash: open dev dashboard
alias comp.dash='comp dash'

## dev

# dd: dev dashboard
alias dd='$HOME/dev/devdash'
# ds: component summary
alias ds='python3 "$HOME/dev/component-scan.sh" summary --color'
# dl: component legend
alias dl='python3 "$HOME/dev/component-scan.sh" legend --color'
# dr: component records
alias dr='python3 "$HOME/dev/component-scan.sh" records'
# dv: component validation
alias dv='python3 "$HOME/dev/component-scan.sh" validate'

## util

# l: unified command legend
l() {
  python3 "$HOME/dev/component-scan.sh" legend --color "$@"
}
