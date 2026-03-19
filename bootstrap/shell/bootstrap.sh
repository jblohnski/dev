## bootstrap

export DEV_BOOTSTRAP_DIR="${DEV_BOOTSTRAP_DIR:-$HOME/dev/bootstrap}"
export DEV_SHELL_DIR="${DEV_SHELL_DIR:-$DEV_BOOTSTRAP_DIR/shell}"
export DEV_ZSHRC_SRC="${DEV_ZSHRC_SRC:-$DEV_BOOTSTRAP_DIR/.zshrc}"
export DEV_BOOTSTRAP_INSTALL="${DEV_BOOTSTRAP_INSTALL:-$DEV_BOOTSTRAP_DIR/install.sh}"

# @component
# @name: Bootstrap Install
# @desc: Sync tracked bootstrap files into their live system counterparts
# @cmd: bi
# @keywords: bootstrap install sync shell git editor
bi() {
  "$DEV_BOOTSTRAP_INSTALL" "$@"
}

# @name: Publish Zsh Link
# @desc: Link tracked zsh config into home and reload current shell
# @cmd: pz
# @keywords: bootstrap shell zsh profile
pz() {
  [[ -f "$DEV_ZSHRC_SRC" ]] || { echo "pz: source not found: $DEV_ZSHRC_SRC"; return 1; }
  command ln -snf "$DEV_ZSHRC_SRC" "$HOME/.zshrc" || return 1
  source "$HOME/.zshrc"
}

# @name: Publish Zsh Copy
# @desc: Copy tracked zsh config into home and reload current shell
# @cmd: pzcp
# @keywords: bootstrap shell zsh profile
pzcp() {
  [[ -f "$DEV_ZSHRC_SRC" ]] || { echo "pzcp: source not found: $DEV_ZSHRC_SRC"; return 1; }
  command cp "$DEV_ZSHRC_SRC" "$HOME/.zshrc" || return 1
  source "$HOME/.zshrc"
}
