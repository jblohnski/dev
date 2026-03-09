[[ -o interactive ]] || return

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

typeset -ga __aliases_before
__aliases_before=("${(@f)$(alias | cut -d= -f1)}")

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

has() { command -v "$1" >/dev/null 2>&1 }

## bootstrap

export DEV_BOOTSTRAP_DIR="$HOME/dev/bootstrap"
export DEV_ZSHRC_SRC="${DEV_ZSHRC_SRC:-$DEV_BOOTSTRAP_DIR/.zshrc}"

# pz: publish tracked zsh config to home and reload current shell
pz() {
  [[ -f "$DEV_ZSHRC_SRC" ]] || { echo "pz: source not found"; return 1; }
  cp "$DEV_ZSHRC_SRC" "$HOME/.zshrc" || return 1
  source "$HOME/.zshrc"
}

## audit

export AUDIT_DIR="$HOME/dev/audit"
export ZEEK_LOG_DIR="${ZEEK_LOG_DIR:-$HOME/zlogs}"

# a: run audit
alias a='builtin cd "$AUDIT_DIR" && ./audit.sh'

# az: zeek controller
az() {
  local cmd="${1:-run}"
  shift || true

  case "$cmd" in
    run)
      builtin cd "$AUDIT_DIR" && ./zeek-audit.sh "$ZEEK_LOG_DIR" "$@"
    ;;
    start)
      local iface="${1:-${ZEEK_CAPTURE_IFACE:-en0}}"
      shift || true
      builtin cd "$AUDIT_DIR" && ./zeek-capture.sh start "$iface" "$@"
    ;;
    stop)
      builtin cd "$AUDIT_DIR" && ./zeek-capture.sh stop
    ;;
    stat|status)
      builtin cd "$AUDIT_DIR" && ./zeek-capture.sh status
    ;;
    merge)
      builtin cd "$AUDIT_DIR" && ./zeek-logsync.sh
    ;;
    uid)
      local uid="${1:?uid required}"
      local run="${2:-uid-$(date +%Y%m%d-%H%M%S)}"
      builtin cd "$AUDIT_DIR" && ./zeek-audit.sh "$ZEEK_LOG_DIR" "$run" -- --uid "$uid"
    ;;
    tuple)
      local src="${1:?src required}"
      local dst="${2:?dst required}"
      local port="${3:?port required}"
      local ts="${4:?timestamp required}"
      local run="${5:-tuple-$(date +%Y%m%d-%H%M%S)}"

      builtin cd "$AUDIT_DIR" && ./zeek-audit.sh "$ZEEK_LOG_DIR" "$run" -- \
        --src-ip "$src" --dst-ip "$dst" --dst-port "$port" --ts "$ts"
    ;;
    *)
      echo "az commands:"
      echo " run start stop stat merge uid tuple"
      return 1
    ;;
  esac
}

# arpt: open latest zeek markdown report path
arpt() {
  local f
  f="$(command ls -1t "$AUDIT_DIR"/report/zeek/zeek-*.md 2>/dev/null | head -n 1 || true)"
  [[ -n "$f" ]] && print "$f" || print "no zeek markdown report found"
}

# azip: zip up audit project only code
azip() {
  zip -r audit.zip audit \
    -x "audit/.git/*" \
    -x "audit/archives/*" \
    -x "audit/__pycache__/*" \
    -x "audit/*/__pycache__/*" \
    -x "audit/*.pyc" \
    -x "audit/*.pyo" \
    -x "audit/baseline/*" \
    -x "audit/current/*" \
    -x "audit/report/*" \
    -x "audit/state/*" \
    -x "audit/*.log" \
    -x "audit/*.pcap*" \
    -x "audit/.DS_Store"
}

## dev

# devzip: zip up only sources for a given directory
devzip() {
  local root="${1:-$HOME/dev}"
  local out="${2:-devsrc.zip}"

  [[ -d "$root" ]] || { echo "devzip: not found"; return 1; }

  (
    cd "$root" || exit
    git ls-files -co --exclude-standard | zip -q "../$out" -@
  )

  echo "created $out"
}

# dz: shorthand for devzip
alias dz='devzip'

# dd: dev dashboard
alias dd='$HOME/dev/devdash'

# ed: open in Sublime
alias ed='subl'

## python

alias py='python3'
alias python='python3'
alias pip='pip3'

## nav

alias ls='ls -G'
alias ll='ls -laG'
alias la='ls -AG'

# tr: tree view
alias tr='tree -C -A -F'

# lt: trimmed tree
lt() {
  command tree -C -A -F -d -L 3 \
    -I 'node_modules|__pycache__|.git|.venv|dist|build'
}

# ltf: lt with files
ltf() {
  command tree -C -A -F \
    -I 'node_modules|__pycache__|.git|.venv|dist|build'
}

setopt AUTO_PUSHD PUSHD_IGNORE_DUPS

# d: directory stack
alias d='dirs -v'

## git

# gs: git status
alias gs='git status -sb'

# gl: git log graph
alias gl='git log --oneline --decorate --graph --all'

# gd: git diff
alias gd='git diff'

# gc: staged diff
alias gc='git diff --cached'

## network

# ips: local IPs
alias ips="ifconfig | awk '/inet /{print \$2}'"

# nc: network connections
alias nc='lsof -nP -i'

# po: listening ports
alias po='lsof -nP -i -sTCP:LISTEN'

# routes: show routes
alias routes='netstat -rn'

# utuns: utun interfaces
alias utuns='ifconfig | grep utun'

## dns

# flushdns: flush DNS
alias flushdns='sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'

# dnscheck: list DNS resolvers
alias dnscheck='scutil --dns'

# sniffdns: capture DNS
alias sniffdns='sudo tcpdump -n -i en0 port 53'

# snihttp: capture HTTP/S
alias snihttp='sudo tcpdump -n -i en0 port 443'

## util

# pa: PATH entries
pa() {
  print -l ${(s/:/)PATH}
}

# e: list env vars
alias e='env | sort'

# grep: grep with color
alias grep='grep --color=auto'

# src: reload zshrc
alias src='source ~/.zshrc'

# c: clear screen
alias c='clear'

# cc: wipe screen
cc() {
  jobs -p | xargs -r kill 2>/dev/null
  clear
}

# cmp: side-by-side diff
cmp() {
  local a="${1:?file1}"
  local b="${2:?file2}"
  vimdiff "$a" "$b"
}

__scan_cmds() {
  awk '
  BEGIN {group="misc"}
  /^## / {sub(/^## /,""); group=tolower($0); next}
  /^# [a-zA-Z0-9_]+:/ {
    name=$2
    sub(/:/,"",name)
    desc=$0
    sub(/^# [^:]+: /,"",desc)
    print group "|" name "|" desc
  }' "$HOME/.zshrc"
}

l() {
  local g name desc
  local last_group=""

  echo
  print -P "${CLR_HDR}commands${CLR_RESET}"

  while IFS='|' read -r g name desc; do

    if [[ "$g" != "$last_group" ]]; then
      print
      print -P " %B%F{15}${g}%f%b"
      last_group="$g"
    fi

    print -P "   ${CLR_NAME}${name}${CLR_RESET}  ${CLR_DESC}${desc}${CLR_RESET}"

  done < <(__scan_cmds)

  echo
}

[[ -z "$__SHELL_LEGEND_DONE" ]] && l && export __SHELL_LEGEND_DONE=1

PROMPT='%F{109}%n@%m%f %F{110}%~%f %F{244}% 🦍 %f'
