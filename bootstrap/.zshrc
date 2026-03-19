export DEV_ROOT="${DEV_ROOT:-$HOME/dev}"
export DEV_BOOTSTRAP_DIR="${DEV_BOOTSTRAP_DIR:-$DEV_ROOT/bootstrap}"
export DEV_SHELL_DIR="${DEV_SHELL_DIR:-$DEV_BOOTSTRAP_DIR/shell}"

if [[ -f "$DEV_SHELL_DIR/dev.sh" ]]; then
  source "$DEV_SHELL_DIR/dev.sh"
else
  echo "bootstrap loader: missing $DEV_SHELL_DIR/dev.sh" >&2
fi
