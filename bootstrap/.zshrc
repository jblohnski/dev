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

# ANSI equivalents (expanded at load time) so network aliases can use the same theme colors
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

## audit
export AUDIT_DIR="$HOME/dev/audit"
export ZEEK_LOG_DIR="${ZEEK_LOG_DIR:-$HOME/zlogs}"

## bootstrap
export DEV_BOOTSTRAP_DIR="$HOME/dev/bootstrap"
export DEV_ZSHRC_SRC="${DEV_ZSHRC_SRC:-$DEV_BOOTSTRAP_DIR/.zshrc}"
# pz: publish tracked zsh config to home and reload current shell
pz() {
  [[ -f "$DEV_ZSHRC_SRC" ]] || { echo "pz: source not found: $DEV_ZSHRC_SRC"; return 1; }
  cp "$DEV_ZSHRC_SRC" "$HOME/.zshrc" || return 1
  source "$HOME/.zshrc"
}

# a: run audit
alias a='builtin cd "$AUDIT_DIR" && ./audit.sh'
# azk: run zeek snapshot workflow
alias azk='builtin cd "$AUDIT_DIR" && ./zeek-audit.sh "$ZEEK_LOG_DIR"'
# azks: start background zeek capture writing logs into $ZEEK_LOG_DIR
azks() {
  local iface="${1:-${ZEEK_CAPTURE_IFACE:-en0}}"
  shift || true
  builtin cd "$AUDIT_DIR" && ./zeek-capture.sh start "$iface" "$@"
}
# azkt: stop background zeek capture
alias azkt='builtin cd "$AUDIT_DIR" && ./zeek-capture.sh stop'
# azkp: show background zeek capture status
alias azkp='builtin cd "$AUDIT_DIR" && ./zeek-capture.sh status'
# azkm: merge stray local zeek logs into $ZEEK_LOG_DIR
alias azkm='builtin cd "$AUDIT_DIR" && ./zeek-logsync.sh'
# azu: zeek by uid
azu() {
  local uid="${1:?uid required}"
  local run="${2:-uid-$(date +%Y%m%d-%H%M%S)}"
  builtin cd "$AUDIT_DIR" && ./zeek-audit.sh "$ZEEK_LOG_DIR" "$run" -- --uid "$uid"
}
# azt: zeek by tuple (src dst port ts [run])
azt() {
  local src="${1:?src_ip required}"
  local dst="${2:?dst_ip required}"
  local port="${3:?dst_port required}"
  local ts="${4:?timestamp required (epoch or ISO)}"
  local run="${5:-tuple-$(date +%Y%m%d-%H%M%S)}"
  builtin cd "$AUDIT_DIR" && ./zeek-audit.sh "$ZEEK_LOG_DIR" "$run" -- \
    --src-ip "$src" --dst-ip "$dst" --dst-port "$port" --ts "$ts"
}
# arpt: open latest zeek markdown report path
arpt() {
  local f
  f="$(command ls -1t "$AUDIT_DIR"/report/zeek/zeek-*.md 2>/dev/null | head -n 1 || true)"
  [[ -n "$f" ]] && print "$f" || print "no zeek markdown report found"
}
# az: zip up audit project only code
az() {
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
    -x "audit/.DS_Store" \
    -x "audit/*/.DS_Store" \
    -x "audit/._*"
}

## dev

# devzip: zip up only sources for a given directory
devzip() {
  local root="${1:-$HOME/dev}"
  local out="${2:-devsrc.zip}"

  [[ -d "$root" ]] || {
    echo "devzip: '$root' not found"
    return 1
  }

  (
    cd "$root" || exit 1

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      # best case: use git index (respects .gitignore and includes dotfiles)
      git ls-files -co --exclude-standard | zip -q "../$out" -@
    else
      # fallback if not a git repo
      find . -type f \
        -not -path "./.git/*" \
        -print | sed 's|^\./||' | zip -q "../$out" -@
    fi
  )

  echo "created $out from $root"
}

# dz: shorthand for devzip
alias dz='devzip'

# dd: dev dashboard
alias dd='$HOME/dev/devdash'

# ed: open in Sublime
alias ed='subl'

## util
alias ls='ls -G'
alias ll='ls -laG'
alias la='ls -AG'
# c: clear screen
alias c='clear'
alias grep='grep --color=auto'
has bat && alias cat='bat -P --color=auto'

# -- python
alias py='python3'
alias python='python3'
alias pip='pip3'
unsetopt PROMPT_SUBST

# -- nav
# tr: tree view
alias tr='tree -C -A -F'
# lt: trimmed tree dirs only to depth 3
lt() {
  command tree -C -A -F -d -L 3 \
    -I 'node_modules|__pycache__|.git|.venv|venv|dist|build|target'
}
# ltf: lt and show files
ltf() {
  command tree -C -A -F \
    -I 'node_modules|__pycache__|.git|.venv|venv|dist|build|target'
}
cd() {
  builtin cd "$@" || return
  ls -laG
}
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS
# d: directory stack
alias d='dirs -v'

# -- git
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
alias ips="ifconfig | awk 'BEGIN{printf \"${ANSI_BOLD}${ANSI_HDR}%-12s %s${ANSI_RESET}\\n\",\"INTERFACE\",\"IPv4\"} /^[a-zA-Z0-9]/{iface=\$1} /inet /{printf \"${ANSI_CYAN}%-12s${ANSI_RESET} ${ANSI_GREEN}%s${ANSI_RESET}\\n\", substr(iface,1,12), \$2}' "

# nc: network connections
alias nc="lsof -nP -i | awk 'NR==1{printf \"${ANSI_BOLD}${ANSI_HDR}%-18s %-7s %-12s %-6s %s${ANSI_RESET}\\n\",\"COMMAND\",\"PID\",\"USER\",\"NODE\",\"NAME\";next}/TCP|UDP/{name=substr(\$0,index(\$0,\$8)+length(\$8)+1);if(\$8==\"TCP\"){printf \"%-18s %-7s %-12s ${ANSI_GREEN}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}else if(\$8==\"UDP\"){printf \"%-18s %-7s %-12s ${ANSI_BLUE}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}else{printf \"%-18s %-7s %-12s %-6s %s\\n\",\$1,\$2,\$3,\$8,name}}' "

# po: listening ports
alias po="lsof -nP -i -sTCP:LISTEN | awk 'NR==1{printf \"${ANSI_BOLD}${ANSI_HDR}%-18s %-7s %-12s %-6s %s${ANSI_RESET}\\n\",\"COMMAND\",\"PID\",\"USER\",\"PROTO\",\"NAME\";next}{name=substr(\$0,index(\$0,\$8)+length(\$8)+1); printf \"%-18s %-7s %-12s ${ANSI_GREEN}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}' "

# routes: show routes
alias routes="netstat -rn | column -t | sed -E '1,3s/(.*)/${ANSI_BOLD}${ANSI_HDR}\1${ANSI_RESET}/' "

# utuns: utun interfaces
alias utuns="ifconfig | awk '/^utun[0-9]*:/ {print \"${ANSI_BOLD}${ANSI_CYAN}\" \$0 \"${ANSI_RESET}\"; in_utun=1; next} /^\s+inet / && in_utun {printf \"    ${ANSI_GREEN}%s${ANSI_RESET}\\n\", \$2; next} /^\S/ && !/^utun[0-9]*:/ {in_utun=0}' "

## dns

# flushdns: flush DNS
alias flushdns='sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'
# dnscheck: list DNS resolvers
alias dnscheck='scutil --dns | sed -n "/resolver #1/,/}/p"'
# sniffdns: capture DNS
alias sniffdns='sudo tcpdump -n -i en0 port 53 or port 5353'
# snihttp: capture HTTP/S
alias snihttp='sudo tcpdump -n -i en0 port 443 or port 80'

# -- util
# pa: PATH entries
pa() {
  print -P "\n${CLR_HDR}path${CLR_RESET}"
  print -l -- ${(s/:/)PATH} | while read p; do
    print -P " ${CLR_NAME}${p}${CLR_RESET}"
  done
  echo
}
# e: list env vars
e() {
  print -P "\n${CLR_HDR}environment${CLR_RESET}\n"
  local -A vars
  local -i max=0
  local key val
  while IFS='=' read -r key val; do
    [[ -z $key ]] && continue
    vars[$key]=$val
    (( ${#key} > max )) && max=${#key}
  done < <(env | sort -f)
  (( max += 2 ))
  for key in "${(@kon)vars}"; do
    print -rP -- " ${CLR_NAME}${(l:$max:: :)key}${CLR_RESET}  ${CLR_DESC}${vars[$key]}${CLR_RESET}"
  done
  print ""
}
# src: reload zshrc
alias src='source ~/.zshrc'
# cc: wipe screen + scrollback + cancel line + kill jobs
cc() {
  jobs -p | xargs -r kill 2>/dev/null
  print -n $'\C-u'
  clear
  printf '\e[3J'
  printf '\e[H'
}
# cmp: side-by-side diff
cmp() {
  local a="${1:?file1 required}"
  local b="${2:?file2 required}"
  if has code; then
    code --diff "$a" "$b"
  elif has subl; then
    subl "$a" "$b"
  else
    command vimdiff "$a" "$b"
  fi
}

__scan_cmds() {
  local file="${ZDOTDIR:-$HOME}/.zshrc"
  command awk '
    function reset_pending(){ pk=""; pd="" }
    BEGIN { reset_pending(); group="misc" }
    /^[[:space:]]*##[[:space:]]+/ {
      line=$0
      sub(/^[[:space:]]*##[[:space:]]+/, "", line)
      group=tolower(line)
      next
    }
    /^[[:space:]]*#[[:space:]]*[A-Za-z0-9_]+:[[:space:]]+/ {
      line=$0
      sub(/^[[:space:]]*#[[:space:]]*/, "", line)
      split(line, a, /:[[:space:]]+/)
      pk=a[1]
      pd=line
      sub(/^[^:]+:[[:space:]]+/, "", pd)
      next
    }
    /^[[:space:]]*alias[[:space:]]+[A-Za-z0-9_]+=/ {
      line=$0
      sub(/^[[:space:]]*alias[[:space:]]+/, "", line)
      split(line, a, /=/)
      name=a[1]
      if (pk != "" && pk == name) {
        print group "|" name "|" pd
      }
      reset_pending()
      next
    }
    /^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*\(\)[[:space:]]*\{/ {
      line=$0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*\(\)[[:space:]]*\{.*/, "", line)
      name=line
      if (pk != "" && pk == name) {
        print group "|" name "|" pd
      }
      reset_pending()
      next
    }
    /^[[:space:]]*[^#[:space:]]/ { reset_pending() }
  ' "$file"
}

l() {
  local -A groups
  local -a order
  local max=0
  local g name desc

  while IFS='|' read -r g name desc; do
    groups[$g]+="${name}|${desc}"$'\n'
    [[ " ${order[*]} " != *" $g "* ]] && order+=("$g")
    (( ${#name} > max )) && max=${#name}
  done < <(__scan_cmds)

  ((max+=2))

  echo
  print -P "${CLR_HDR}commands${CLR_RESET}"

  local first=1
  for g in "${order[@]}"; do
    [[ $first -eq 0 ]] && echo
    first=0
    print -P " %B%F{15}${g}%f%b"
    while IFS='|' read -r n d; do
      [[ -z "$n" ]] && continue
      print -P " ${CLR_NAME}$(printf "%-${max}s" "$n")${CLR_RESET}${CLR_DESC}${d}${CLR_RESET}"
    done <<< "${groups[$g]}"
  done
  echo
}

[[ -z "$__SHELL_LEGEND_DONE" ]] && l && export __SHELL_LEGEND_DONE=1

PROMPT='%F{109}%n@%m%f %F{110}%~%f %F{244}% 🦍 %f'

source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
eval "$(zoxide init zsh)"
