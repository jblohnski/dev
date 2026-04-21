#!/usr/bin/env bash
# dev-cmd: alias=init name="Bootstrap Install" group=sys run=user desc="Sync tracked bootstrap files into their live system counterparts"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link_mode=1
dry_run=0

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [--copy] [--dry-run]

Behavior:
  - links or copies tracked bootstrap files into their live home locations
  - intended for dotfiles maintained in ~/dev/bootstrap

Targets:
  .zshrc -> ~/.zshrc
  .gitconfig -> ~/.gitconfig
  .editorconfig -> ~/.editorconfig
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --copy)
      link_mode=0
      shift
      ;;
    --link)
      link_mode=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

sync_one() {
  local src="$1"
  local dst="$2"

  if [[ ! -e "$src" ]]; then
    echo "skip missing: $src" >&2
    return 0
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    if [[ "$link_mode" -eq 1 ]]; then
      printf 'link %s -> %s\n' "$src" "$dst"
    else
      printf 'copy %s -> %s\n' "$src" "$dst"
    fi
    return 0
  fi

  if [[ "$link_mode" -eq 1 ]]; then
    ln -snf "$src" "$dst"
    printf 'linked %s -> %s\n' "$src" "$dst"
  else
    cp "$src" "$dst"
    printf 'copied %s -> %s\n' "$src" "$dst"
  fi
}

sync_one "$ROOT_DIR/.zshrc" "$HOME/.zshrc"
sync_one "$ROOT_DIR/.gitconfig" "$HOME/.gitconfig"
sync_one "$ROOT_DIR/.editorconfig" "$HOME/.editorconfig"
