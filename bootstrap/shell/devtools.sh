## dev

# dev-cmd: alias=devzip name="Dev Zip" group=sys run=user desc="Zip up only sources for a given directory"
devzip() {
  local root="${1:-$HOME/dev}"
  local out="${2:-devsrc.zip}"

  [[ -d "$root" ]] || {
    echo "devzip: '$root' not found"
    return 1
  }

  (
    cd "$root" || exit 1

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git ls-files -co --exclude-standard | zip -q "../$out" -@
    else
      find . -type f \
        -not -path "./.git/*" \
        -print | sed 's|^\./||' | zip -q "../$out" -@
    fi
  )

  echo "created $out from $root"
}

# dev-cmd: alias=dz name="Dev Zip Alias" group=sys run=user desc="Shorthand for devzip"
alias dz='devzip'

# dev-cmd: alias=ed name=Edit group=sys run=user legend=hide desc="Open in Sublime"
alias ed='subl'

# dev-cmd: alias=gorilla name=Gorilla group=sys run=user desc="Run the local gorilla entrypoint when installed"
gorilla() {
  local bin=""
  bin="$(whence -p gorilla 2>/dev/null || true)"
  if [[ -n "$bin" ]]; then
    "$bin" "$@"
    return $?
  fi

  bin="$(whence -p gorilla-cli 2>/dev/null || true)"
  if [[ -n "$bin" ]]; then
    "$bin" "$@"
    return $?
  fi

  print "gorilla: no executable found in PATH (checked: gorilla, gorilla-cli)"
  return 127
}
