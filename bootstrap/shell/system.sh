## python

# @component
# @name: Python 3
# @desc: Use Python 3 for python shortcuts
# @cmd: py
# @keywords: dev python shell
alias py='python3'
alias python='python3'
alias pip='pip3'

## nav

alias ls='ls -G'
alias ll='ls -laG'
alias la='ls -AG'

# @component
# @name: Tree
# @desc: Tree view
# @cmd: tr
# @keywords: dev nav tree
alias tr='tree -C -A -F'

# @name: Tree Dirs
# @desc: Show trimmed tree directories to depth 3
# @cmd: lt
# @keywords: dev nav tree
lt() {
  command tree -C -A -F -d -L 3 \
    -I 'node_modules|__pycache__|.git|.venv|venv|dist|build|target'
}

# @name: Tree Full
# @desc: Show trimmed tree with files
# @cmd: ltf
# @keywords: dev nav tree
ltf() {
  command tree -C -A -F \
    -I 'node_modules|__pycache__|.git|.venv|venv|dist|build|target'
}

cd() {
  builtin cd "$@" || return
  ls -laG
}

setopt AUTO_PUSHD PUSHD_IGNORE_DUPS

# @name: Dirs
# @desc: Show directory stack
# @cmd: d
# @keywords: dev nav dirs
alias d='dirs -v'

## git

# @component
# @name: Git Status
# @desc: Git status
# @cmd: gs
# @keywords: dev git status
alias gs='git status -sb'

# @name: Git Log
# @desc: Git log graph
# @cmd: gl
# @keywords: dev git log
alias gl='git log --oneline --decorate --graph --all'

# @name: Git Diff
# @desc: Git diff
# @cmd: gd
# @keywords: dev git diff
alias gd='git diff'

# @name: Git Cached Diff
# @desc: Staged diff
# @cmd: gc
# @keywords: dev git diff
alias gc='git diff --cached'

## network

# @component
# @name: IPs
# @desc: List local IPv4 addresses
# @cmd: ips
# @keywords: dev network ip
alias ips="ifconfig | awk 'BEGIN{printf \"${ANSI_BOLD}${ANSI_HDR}%-12s %s${ANSI_RESET}\\n\",\"INTERFACE\",\"IPv4\"} /^[a-zA-Z0-9]/{iface=\$1} /inet /{printf \"${ANSI_CYAN}%-12s${ANSI_RESET} ${ANSI_GREEN}%s${ANSI_RESET}\\n\", substr(iface,1,12), \$2}' "

# @name: Connections
# @desc: Show network connections
# @cmd: nc
# @keywords: dev network sockets
alias nc="lsof -nP -i | awk 'NR==1{printf \"${ANSI_BOLD}${ANSI_HDR}%-18s %-7s %-12s %-6s %s${ANSI_RESET}\\n\",\"COMMAND\",\"PID\",\"USER\",\"NODE\",\"NAME\";next}/TCP|UDP/{name=substr(\$0,index(\$0,\$8)+length(\$8)+1);if(\$8==\"TCP\"){printf \"%-18s %-7s %-12s ${ANSI_GREEN}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}else if(\$8==\"UDP\"){printf \"%-18s %-7s %-12s ${ANSI_BLUE}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}else{printf \"%-18s %-7s %-12s %-6s %s\\n\",\$1,\$2,\$3,\$8,name}}' "

# @name: Ports
# @desc: Show listening ports
# @cmd: po
# @keywords: dev network ports
alias po="lsof -nP -i -sTCP:LISTEN | awk 'NR==1{printf \"${ANSI_BOLD}${ANSI_HDR}%-18s %-7s %-12s %-6s %s${ANSI_RESET}\\n\",\"COMMAND\",\"PID\",\"USER\",\"PROTO\",\"NAME\";next}{name=substr(\$0,index(\$0,\$8)+length(\$8)+1); printf \"%-18s %-7s %-12s ${ANSI_GREEN}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}' "

# @name: Routes
# @desc: Show routes
# @cmd: routes
# @keywords: dev network routes
alias routes="netstat -rn | column -t | sed -E '1,3s/(.*)/${ANSI_BOLD}${ANSI_HDR}\1${ANSI_RESET}/' "

# @name: UTUNs
# @desc: Show utun interfaces
# @cmd: utuns
# @keywords: dev network utun
alias utuns="ifconfig | awk '/^utun[0-9]*:/ {print \"${ANSI_BOLD}${ANSI_CYAN}\" \$0 \"${ANSI_RESET}\"; in_utun=1; next} /^\s+inet / && in_utun {printf \"    ${ANSI_GREEN}%s${ANSI_RESET}\\n\", \$2; next} /^\S/ && !/^utun[0-9]*:/ {in_utun=0}' "

## dns

# @component
# @name: Flush DNS
# @desc: Flush DNS caches
# @cmd: flushdns
# @keywords: dev dns cache
alias flushdns='sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'

# @name: DNS Check
# @desc: List DNS resolvers
# @cmd: dnscheck
# @keywords: dev dns resolvers
alias dnscheck='scutil --dns | sed -n "/resolver #1/,/}/p"'

# @name: DNS Sniff
# @desc: Capture DNS traffic
# @cmd: sniffdns
# @keywords: dev dns capture
alias sniffdns='sudo tcpdump -n -i en0 port 53 or port 5353'

# @name: HTTP Sniff
# @desc: Capture HTTP and HTTPS traffic
# @cmd: snihttp
# @keywords: dev http capture
alias snihttp='sudo tcpdump -n -i en0 port 443 or port 80'

## util

# @component
# @name: PATH
# @desc: Print PATH entries
# @cmd: pa
# @keywords: dev util path
pa() {
  print -P "\n${CLR_HDR}path${CLR_RESET}"
  print -l -- ${(s/:/)PATH} | while read -r p; do
    print -P " ${CLR_NAME}${p}${CLR_RESET}"
  done
  echo
}

# @name: Env
# @desc: List environment variables
# @cmd: e
# @keywords: dev util env
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

# @name: Grep
# @desc: Grep with color
# @cmd: grep
# @keywords: dev util text
alias grep='grep --color=auto'
has bat && alias cat='bat -P --color=auto'

# @name: Source
# @desc: Reload zshrc
# @cmd: src
# @keywords: dev shell zsh
alias src='source ~/.zshrc'

# @name: Clear
# @desc: Clear screen
# @cmd: c
# @keywords: dev util terminal
alias c='clear'

# @name: Clear Hard
# @desc: Wipe screen, scrollback, and background jobs
# @cmd: cc
# @keywords: dev util terminal
cc() {
  jobs -p | xargs -r kill 2>/dev/null
  print -n $'\C-u'
  clear
  printf '\e[3J'
  printf '\e[H'
}

# @name: Compare
# @desc: Side-by-side diff
# @cmd: cmp
# @keywords: dev util diff
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
