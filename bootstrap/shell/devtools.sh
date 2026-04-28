## dev

# dev-cmd: alias=devzip name=devzip group=sys run=user desc="Zip up only sources for a given directory"
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

alias dz='devzip'

alias ed='subl'
