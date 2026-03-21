## python

# dev-cmd: alias=py name="Python 3" group=sys run=user legend=hide desc="Use Python 3 for python shortcuts"
alias py='python3'
alias python='python3'
alias pip='pip3'

## nav

alias ls='ls -G'
alias ll='ls -laG'
alias la='ls -AG'

# dev-cmd: alias=tr name=Tree group=sys run=user legend=hide desc="Tree view"
alias tr='tree -C -A -F'

# dev-cmd: alias=lt name="Tree Dirs" group=sys run=user legend=hide desc="Show trimmed tree directories to depth 3"
lt() {
  command tree -C -A -F -d -L 3 \
    -I 'node_modules|__pycache__|.git|.venv|venv|dist|build|target'
}

# dev-cmd: alias=ltf name="Tree Full" group=sys run=user legend=hide desc="Show trimmed tree with files"
ltf() {
  command tree -C -A -F \
    -I 'node_modules|__pycache__|.git|.venv|venv|dist|build|target'
}

cd() {
  builtin cd "$@" || return
  ls -laG
}

setopt AUTO_PUSHD PUSHD_IGNORE_DUPS

# dev-cmd: alias=d name=Dirs group=sys run=user legend=hide desc="Show directory stack"
alias d='dirs -v'

## git

# dev-cmd: alias=gs name="Git Status" group=sys run=user legend=hide desc="Git status"
alias gs='git status -sb'

# dev-cmd: alias=gl name="Git Log" group=sys run=user legend=hide desc="Git log graph"
alias gl='git log --oneline --decorate --graph --all'

# dev-cmd: alias=gd name="Git Diff" group=sys run=user legend=hide desc="Git diff"
alias gd='git diff'

# dev-cmd: alias=gc name="Git Cached Diff" group=sys run=user legend=hide desc="Staged diff"
alias gc='git diff --cached'

## network

# dev-cmd: alias=ips name=IPs group=net run=user desc="List local IPv4 addresses"
alias ips="ifconfig | awk 'BEGIN{printf \"${ANSI_BOLD}${ANSI_HDR}%-12s %s${ANSI_RESET}\\n\",\"INTERFACE\",\"IPv4\"} /^[a-zA-Z0-9]/{iface=\$1} /inet /{printf \"${ANSI_CYAN}%-12s${ANSI_RESET} ${ANSI_GREEN}%s${ANSI_RESET}\\n\", substr(iface,1,12), \$2}' "

# dev-cmd: alias=nc name=Connections group=net run=user desc="Show network connections"
alias nc="lsof -nP -i | awk 'NR==1{printf \"${ANSI_BOLD}${ANSI_HDR}%-18s %-7s %-12s %-6s %s${ANSI_RESET}\\n\",\"COMMAND\",\"PID\",\"USER\",\"NODE\",\"NAME\";next}/TCP|UDP/{name=substr(\$0,index(\$0,\$8)+length(\$8)+1);if(\$8==\"TCP\"){printf \"%-18s %-7s %-12s ${ANSI_GREEN}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}else if(\$8==\"UDP\"){printf \"%-18s %-7s %-12s ${ANSI_BLUE}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}else{printf \"%-18s %-7s %-12s %-6s %s\\n\",\$1,\$2,\$3,\$8,name}}' "

# dev-cmd: alias=po name=Ports group=net run=user desc="Show listening ports"
alias po="lsof -nP -i -sTCP:LISTEN | awk 'NR==1{printf \"${ANSI_BOLD}${ANSI_HDR}%-18s %-7s %-12s %-6s %s${ANSI_RESET}\\n\",\"COMMAND\",\"PID\",\"USER\",\"PROTO\",\"NAME\";next}{name=substr(\$0,index(\$0,\$8)+length(\$8)+1); printf \"%-18s %-7s %-12s ${ANSI_GREEN}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}' "

# dev-cmd: alias=routes name=Routes group=net run=user desc="Show routes"
alias routes="netstat -rn | column -t | sed -E '1,3s/(.*)/${ANSI_BOLD}${ANSI_HDR}\1${ANSI_RESET}/' "

# dev-cmd: alias=utuns name=UTUNs group=net run=user desc="Show utun interfaces"
alias utuns="ifconfig | awk '/^utun[0-9]*:/ {print \"${ANSI_BOLD}${ANSI_CYAN}\" \$0 \"${ANSI_RESET}\"; in_utun=1; next} /^\s+inet / && in_utun {printf \"    ${ANSI_GREEN}%s${ANSI_RESET}\\n\", \$2; next} /^\S/ && !/^utun[0-9]*:/ {in_utun=0}' "

## dns

# dev-cmd: alias=flushdns name="Flush DNS" group=net run=user desc="Flush DNS caches"
alias flushdns='sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'

# dev-cmd: alias=dnscheck name="DNS Check" group=net run=user desc="List DNS resolvers"
alias dnscheck='scutil --dns | sed -n "/resolver #1/,/}/p"'

# dev-cmd: alias=sniffdns name="DNS Sniff" group=net run=user desc="Capture DNS traffic"
alias sniffdns='sudo tcpdump -n -i en0 port 53 or port 5353'

# dev-cmd: alias=snihttp name="HTTP Sniff" group=net run=user desc="Capture HTTP and HTTPS traffic"
alias snihttp='sudo tcpdump -n -i en0 port 443 or port 80'

## util

# dev-cmd: alias=pa name=PATH group=sys run=user legend=hide desc="Print PATH entries"
pa() {
  print -P "\n${CLR_HDR}path${CLR_RESET}"
  print -l -- ${(s/:/)PATH} | while read -r p; do
    print -P " ${CLR_NAME}${p}${CLR_RESET}"
  done
  echo
}

# dev-cmd: alias=e name=Env group=sys run=user legend=hide desc="List environment variables"
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

# dev-cmd: alias=grep name=Grep group=sys run=user legend=hide desc="Grep with color"
alias grep='grep --color=auto'
has bat && alias cat='bat -P --color=auto'

# dev-cmd: alias=src name=Source group=sys run=user legend=hide desc="Reload zshrc"
alias src='source ~/.zshrc'

# dev-cmd: alias=c name=Clear group=sys run=user legend=hide desc="Clear screen"
alias c='clear'

# dev-cmd: alias=cc name="Clear Hard" group=sys run=user legend=hide desc="Wipe screen, scrollback, and background jobs"
cc() {
  jobs -p | xargs -r kill 2>/dev/null
  print -n $'\C-u'
  clear
  printf '\e[3J'
  printf '\e[H'
}

# dev-cmd: alias=cmp name=Compare group=sys run=user legend=hide desc="Side-by-side diff"
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
