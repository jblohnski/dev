## dev

export DEV_ROOT="${DEV_ROOT:-$HOME/dev}"
export DEV_SCAN="${DEV_SCAN:-$DEV_ROOT/component-scan.sh}"

# dev-cmd: alias=comp name="Dev Inventory" group=sys run=user legend=hide desc="Run summary, legend, validate, manifest, or dashboard"
comp() {
  local cmd="${1:-summary}"
  [[ $# -gt 0 ]] && shift

  case "$cmd" in
    summary|scan)
      python3 "$DEV_SCAN" summary --color "$@"
      ;;
    legend)
      python3 "$DEV_SCAN" legend --color "$@"
      ;;
    validate)
      python3 "$DEV_SCAN" validate "$@"
      ;;
    manifest)
      python3 "$DEV_SCAN" manifest "$@"
      ;;
    dash)
      "$DEV_ROOT/devdash" "$@"
      ;;
    *)
      echo "comp commands: summary legend validate manifest dash"
      return 1
      ;;
  esac
}

## dev

# dev-cmd: alias=dd name="Dev Dashboard" group=sys run=user legend=hide desc="Open dev dashboard"
alias dd='$DEV_ROOT/devdash'
# dev-cmd: alias=ds name=Summary group=sys run=user legend=hide desc="Show component summary"
alias ds='comp summary'
# dev-cmd: alias=dl name=Legend group=sys run=user legend=hide desc="Show unified command legend"
alias dl='comp legend'
# dev-cmd: alias=dv name=Validation group=sys run=user legend=hide desc="Validate component metadata and taxonomy"
alias dv='comp validate'

## util

# dev-cmd: alias=l name=Legend group=sys run=user legend=hide desc="Show unified command legend"
l() {
  comp legend "$@"
}

dev_publish_discovered_commands() {
  local alias_name rel_path runmode alias_value
  while IFS=$'\t' read -r alias_name rel_path runmode; do
    [[ -n "$alias_name" && -n "$rel_path" ]] || continue
    if (( ${+aliases[$alias_name]} || ${+functions[$alias_name]} )); then
      continue
    fi
    if [[ "$runmode" == "sudo" ]]; then
      alias_value="sudo \"\$DEV_ROOT/$rel_path\""
    else
      alias_value="\"\$DEV_ROOT/$rel_path\""
    fi
    alias -- "$alias_name=$alias_value"
  done < <(python3 "$DEV_SCAN" shell)
}
