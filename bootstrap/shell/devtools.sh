## dev

# @component
# @name: Dev Zip
# @desc: Zip up only sources for a given directory
# @cmd: devzip
# @keywords: dev archive sources
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

# @name: Dev Zip Alias
# @desc: Shorthand for devzip
# @cmd: dz
# @keywords: dev archive alias
alias dz='devzip'

# @name: Edit
# @desc: Open in Sublime
# @cmd: ed
# @keywords: dev editor shell
alias ed='subl'

# @name: Gorilla
# @desc: Run the local gorilla entrypoint when installed
# @cmd: gorilla
# @keywords: dev ai cli
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
