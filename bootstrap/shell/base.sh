export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export SHELL_SESSIONS_DISABLE=1
autoload -Uz colors && colors

CLR_HDR="%F{110}"
CLR_NAME="%F{153}"
CLR_DESC="%F{244}"
CLR_ACCENT="%F{109}"
CLR_RESET="%f"

ANSI_BOLD='\033[1m'
ANSI_RESET='\033[0m'
ANSI_HDR='\033[38;5;110m'
ANSI_CYAN='\033[36m'
ANSI_GREEN='\033[32m'
ANSI_BLUE='\033[34m'

HISTFILE="$HOME/.zsh_history"
HISTSIZE=500
SAVEHIST=500
setopt HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS INC_APPEND_HISTORY
setopt NO_BEEP INTERACTIVE_COMMENTS

typeset -U path PATH
path=(
  /opt/homebrew/opt/python@3.12/libexec/bin
  /opt/homebrew/bin
  /opt/homebrew/sbin
  /Users/jagov/bin
  /usr/bin
  /bin
  /usr/sbin
  /sbin
)
export PATH

if [[ -d /opt/homebrew/share/zsh/site-functions ]]; then
  fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
fi

autoload -Uz compinit
compinit -d ~/.zcompdump

export MANPATH="/opt/homebrew/share/man${MANPATH:+:$MANPATH}"
export INFOPATH="/opt/homebrew/share/info${INFOPATH:+:$INFOPATH}"

has() { command -v "$1" >/dev/null 2>&1; }

source_if_exists() {
  local file="$1"
  [[ -f "$file" ]] && source "$file"
}

source_if_exists /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source_if_exists /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Pin prompt behavior so Terminal.app gets color expansion and stable inline prompt rendering.
setopt PROMPT_PERCENT PROMPT_CR PROMPT_SP
unsetopt PROMPT_SUBST TRANSIENT_RPROMPT

PROMPT='%F{109}%n@%m%f %F{110}%~%f %F{109}🦍%f %F{244}>%f '
RPROMPT=''
