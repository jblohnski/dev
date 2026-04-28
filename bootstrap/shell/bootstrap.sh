## bootstrap

export DEV_BOOTSTRAP_DIR="${DEV_BOOTSTRAP_DIR:-$HOME/dev/bootstrap}"
export DEV_SHELL_DIR="${DEV_SHELL_DIR:-$DEV_BOOTSTRAP_DIR/shell}"
export DEV_ZSHRC_SRC="${DEV_ZSHRC_SRC:-$DEV_BOOTSTRAP_DIR/.zshrc}"
export DEV_BOOTSTRAP_INSTALL="${DEV_BOOTSTRAP_INSTALL:-$DEV_BOOTSTRAP_DIR/install.sh}"

# dev-cmd: alias=pz name=zsh-link group=sys run=user desc="Link zsh config"
pz() {
  [[ -f "$DEV_ZSHRC_SRC" ]] || { echo "pz: source not found: $DEV_ZSHRC_SRC"; return 1; }
  command ln -snf "$DEV_ZSHRC_SRC" "$HOME/.zshrc" || return 1
  source "$HOME/.zshrc"
}

# dev-cmd: alias=pzcp name=zsh-copy group=sys run=user desc="Copy zsh config"
pzcp() {
  [[ -f "$DEV_ZSHRC_SRC" ]] || { echo "pzcp: source not found: $DEV_ZSHRC_SRC"; return 1; }
  command cp "$DEV_ZSHRC_SRC" "$HOME/.zshrc" || return 1
  source "$HOME/.zshrc"
}
