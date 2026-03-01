#!/usr/bin/env bash
set -euo pipefail

SRC="${1:-$HOME/dev/.zshrc}"
DST="${2:-$HOME/.zshrc}"

if [[ ! -f "$SRC" ]]; then
  echo "publish-zshrc: source not found: $SRC" >&2
  exit 1
fi

command -v zsh >/dev/null 2>&1 || {
  echo "publish-zshrc: zsh not found" >&2
  exit 1
}

zsh -n "$SRC"

if [[ -f "$DST" ]] && cmp -s "$SRC" "$DST"; then
  echo "publish-zshrc: already current"
  exit 0
fi

if [[ -f "$DST" ]]; then
  ts="$(date +%Y%m%d_%H%M%S)"
  bak="${DST}.bak.${ts}"
  cp "$DST" "$bak"
  echo "publish-zshrc: backup -> $bak"
fi

cp "$SRC" "$DST"
chmod 0644 "$DST"

echo "publish-zshrc: published $SRC -> $DST"
echo "publish-zshrc: reload with 'source ~/.zshrc'"
