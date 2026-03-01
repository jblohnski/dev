[[ -o interactive ]] || return

DEV_ZSHRC="$HOME/dev/bootstrap/zsh/.zshrc"

if [[ -f "$DEV_ZSHRC" ]]; then
  source "$DEV_ZSHRC"
else
  print -u2 -- "missing tracked profile: $DEV_ZSHRC"
  return 1
fi
