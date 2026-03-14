## dev

# @component
# @name: Component Inventory
# @desc: Run the shared component inventory entrypoint
# @cmd: comp
# @keywords: dev inventory taxonomy commands
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

# @name: Component Summary
# @desc: Show component summary
# @cmd: comp.scan
# @keywords: dev inventory summary taxonomy
alias comp.scan='comp scan'
# @name: Component Legend
# @desc: Show unified command legend
# @cmd: comp.legend
# @keywords: dev inventory legend taxonomy
alias comp.legend='comp legend'
# @name: Component Records
# @desc: Emit component records
# @cmd: comp.records
# @keywords: dev inventory records taxonomy
alias comp.records='comp records'
# @name: Component Validation
# @desc: Validate component metadata and taxonomy
# @cmd: comp.validate
# @keywords: dev inventory validate taxonomy
alias comp.validate='comp validate'
# @name: Component Dashboard
# @desc: Open dev dashboard
# @cmd: comp.dash
# @keywords: dev inventory dashboard taxonomy
alias comp.dash='comp dash'

## dev

# @name: Dev Dashboard
# @desc: Open dev dashboard
# @cmd: dd
# @keywords: dev dashboard inventory
alias dd='$HOME/dev/devdash'
# @name: Summary
# @desc: Show component summary
# @cmd: ds
# @keywords: dev summary inventory
alias ds='python3 "$HOME/dev/component-scan.sh" summary --color'
# @name: Legend
# @desc: Show component legend
# @cmd: dl
# @keywords: dev legend inventory
alias dl='python3 "$HOME/dev/component-scan.sh" legend --color'
# @name: Records
# @desc: Emit component records
# @cmd: dr
# @keywords: dev records inventory
alias dr='python3 "$HOME/dev/component-scan.sh" records'
# @name: Validation
# @desc: Validate component metadata
# @cmd: dv
# @keywords: dev validate inventory taxonomy
alias dv='python3 "$HOME/dev/component-scan.sh" validate'

## util

# @component
# @name: Legend
# @desc: Show unified command legend
# @cmd: l
# @keywords: dev legend inventory taxonomy
l() {
  python3 "$HOME/dev/component-scan.sh" legend --color "$@"
}
