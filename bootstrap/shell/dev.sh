[[ -o interactive ]] || return

export DEV_ROOT="${DEV_ROOT:-$HOME/dev}"
export DEV_BOOTSTRAP_DIR="${DEV_BOOTSTRAP_DIR:-$HOME/dev/bootstrap}"
export DEV_SHELL_DIR="${DEV_SHELL_DIR:-$DEV_BOOTSTRAP_DIR/shell}"
export DEV_ZSHRC_SRC="${DEV_ZSHRC_SRC:-$DEV_BOOTSTRAP_DIR/.zshrc}"

for shell_file in \
  "$DEV_SHELL_DIR/base.sh" \
  "$DEV_SHELL_DIR/inventory.sh" \
  "$DEV_SHELL_DIR/bootstrap.sh" \
  "$DEV_SHELL_DIR/audit.sh" \
  "$DEV_SHELL_DIR/system.sh" \
  "$DEV_SHELL_DIR/devtools.sh"
do
  [[ -f "$shell_file" ]] && source "$shell_file"
done

if typeset -f dev_publish_discovered_commands >/dev/null 2>&1; then
  dev_publish_discovered_commands
fi

if [[ "${DEV_SHELL_SHOW_LEGEND:-0}" == "1" ]] && [[ -z "${__SHELL_LEGEND_DONE:-}" ]]; then
  l
  export __SHELL_LEGEND_DONE=1
fi
