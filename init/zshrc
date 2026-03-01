# ------------------------------------------------------------------------------
# Interactive only
# ------------------------------------------------------------------------------
[[ -o interactive ]] || return

# ------------------------------------------------------------------------------
# History
# ------------------------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS INC_APPEND_HISTORY
setopt NO_BEEP INTERACTIVE_COMMENTS

# ------------------------------------------------------------------------------
# PATH (explicit, stable)
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# Completions (Homebrew)
# ------------------------------------------------------------------------------
if [[ -d /opt/homebrew/share/zsh/site-functions ]]; then
  fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
fi

autoload -Uz compinit
compinit -d ~/.zcompdump

# ------------------------------------------------------------------------------
# Homebrew docs (no PATH mutation)
# ------------------------------------------------------------------------------
export MANPATH="/opt/homebrew/share/man${MANPATH:+:$MANPATH}"
export INFOPATH="/opt/homebrew/share/info${INFOPATH:+:$INFOPATH}"

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
has() { command -v "$1" >/dev/null 2>&1 }

# ------------------------------------------------------------------------------
# Core aliases
# ------------------------------------------------------------------------------
alias ls='ls -G'
alias ll='ls -la'
alias la='ls -A'
alias c='clear'

# ------------------------------------------------------------------------------
# grep / cat coloring
# ------------------------------------------------------------------------------
alias grep='grep --color=auto'
has bat && alias cat='bat -P --color=auto'

# ------------------------------------------------------------------------------
# Node + Python
# ------------------------------------------------------------------------------
export NODE_REPL_HISTORY="$HOME/.node_repl_history"
export PIP_DISABLE_PIP_VERSION_CHECK=0
export VIRTUAL_ENV_DISABLE_PROMPT=0

alias py='python3'
alias python='python3'

# ------------------------------------------------------------------------------
# Tree helper
# ------------------------------------------------------------------------------
lt() {
  command tree -d -L 3 -C -A \
    -I 'node_modules|__pycache__|.git|.venv|venv|dist|build|target'
}

# ------------------------------------------------------------------------------
# cd helper (safe)
# ------------------------------------------------------------------------------
cd() {
  builtin cd "$@" || return
  ls -la
}

# ------------------------------------------------------------------------------
# Directory stack
# ------------------------------------------------------------------------------
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS
alias d='dirs -v'

# ------------------------------------------------------------------------------
# Git shortcuts
# ------------------------------------------------------------------------------
alias gs='git status -sb'
alias gl='git log --oneline --decorate --graph --all'
alias gd='git diff'
alias gdc='git diff --cached'

# ------------------------------------------------------------------------------
# Network helpers
# ------------------------------------------------------------------------------
alias ips='ifconfig | grep "inet "'
alias ports='lsof -nP -iTCP -sTCP:LISTEN'
alias flushdns='sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'
alias dnscheck='scutil --dns | sed -n "/resolver #1/,/}/p"'
alias sniffdns='sudo tcpdump -n -i any port 53'
alias snifftls='sudo tcpdump -n -i any port 443'

# ------------------------------------------------------------------------------
# Prompt (ghost-free, Terminal.app safe)
# ------------------------------------------------------------------------------
autoload -Uz colors && colors

PROMPT='%{%F{75}%}%n@%m %{%F{110}%}%~%{%f%} %{%F{244}%}$%{%f%} '
# RPROMPT='%{%F{244}%}🦍%{%f%}'
