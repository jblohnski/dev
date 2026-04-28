## dev

alias sudo='sudo '

## python

alias py='python3'
alias python='python3'
alias pip='pip3'

## nav

alias ls='ls -G'
alias ll='ls -laG'
alias la='ls -AG'

alias tr='tree -C -A -F'

lt() {
  command tree -C -A -F -d -L 3 \
    -I 'node_modules|__pycache__|.git|.venv|venv|dist|build|target'
}

ltf() {
  command tree -C -A -F \
    -I 'node_modules|__pycache__|.git|.venv|venv|dist|build|target'
}

cd() {
  builtin cd "$@" || return
  ls -laG
}

setopt AUTO_PUSHD PUSHD_IGNORE_DUPS

alias d='dirs -v'

## git

alias gs='git status -sb'

alias gl='git log --oneline --decorate --graph --all'

alias gd='git diff'

alias gc='git diff --cached'

## network

# dev-cmd: alias=ips name=ips group=net run=user desc="List local IPv4 addresses"
alias ips="ifconfig | awk 'BEGIN{printf \"${ANSI_BOLD}${ANSI_HDR}%-12s %s${ANSI_RESET}\\n\",\"INTERFACE\",\"IPv4\"} /^[a-zA-Z0-9]/{iface=\$1} /inet /{printf \"${ANSI_CYAN}%-12s${ANSI_RESET} ${ANSI_GREEN}%s${ANSI_RESET}\\n\", substr(iface,1,12), \$2}' "

# dev-cmd: alias=nc name=netconn group=net run=user desc="Show sockets"
alias nc="lsof -nP -i | awk 'NR==1{printf \"${ANSI_BOLD}${ANSI_HDR}%-18s %-7s %-12s %-6s %s${ANSI_RESET}\\n\",\"COMMAND\",\"PID\",\"USER\",\"NODE\",\"NAME\";next}/TCP|UDP/{name=substr(\$0,index(\$0,\$8)+length(\$8)+1);if(\$8==\"TCP\"){printf \"%-18s %-7s %-12s ${ANSI_GREEN}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}else if(\$8==\"UDP\"){printf \"%-18s %-7s %-12s ${ANSI_BLUE}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}else{printf \"%-18s %-7s %-12s %-6s %s\\n\",\$1,\$2,\$3,\$8,name}}' "

# dev-cmd: alias=po name=ports group=net run=user desc="Show listeners"
alias po="lsof -nP -i -sTCP:LISTEN | awk 'NR==1{printf \"${ANSI_BOLD}${ANSI_HDR}%-18s %-7s %-12s %-6s %s${ANSI_RESET}\\n\",\"COMMAND\",\"PID\",\"USER\",\"PROTO\",\"NAME\";next}{name=substr(\$0,index(\$0,\$8)+length(\$8)+1); printf \"%-18s %-7s %-12s ${ANSI_GREEN}%-6s${ANSI_RESET} %s\\n\",\$1,\$2,\$3,\$8,name}' "

# dev-cmd: alias=rte name=routes group=net run=user desc="Show routes"
alias rte="netstat -rn | column -t | sed -E '1,3s/(.*)/${ANSI_BOLD}${ANSI_HDR}\1${ANSI_RESET}/' "
alias routes='rte'

# dev-cmd: alias=utn name=utuns group=net run=user desc="Show utun links"
alias utn="ifconfig | awk '/^utun[0-9]*:/ {print \"${ANSI_BOLD}${ANSI_CYAN}\" \$0 \"${ANSI_RESET}\"; in_utun=1; next} /^\s+inet / && in_utun {printf \"    ${ANSI_GREEN}%s${ANSI_RESET}\\n\", \$2; next} /^\S/ && !/^utun[0-9]*:/ {in_utun=0}' "
alias utuns='utn'

## dns

# dev-cmd: alias=fdns name=flushdns group=net run=user desc="Flush DNS"
alias fdns='sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'
alias flushdns='fdns'

# dev-cmd: alias=dns name=dnscheck group=net run=user desc="List DNS"
alias dns='scutil --dns | sed -n "/resolver #1/,/}/p"'
alias dnscheck='dns'

# dev-cmd: alias=sdns name=sniffdns group=net run=user desc="Capture DNS"
alias sdns='sudo tcpdump -n -i en0 port 53 or port 5353'
alias sniffdns='sdns'

# dev-cmd: alias=http name=snihttp group=net run=user desc="Capture web traffic"
alias http='sudo tcpdump -n -i en0 port 443 or port 80'
alias snihttp='http'

## util

pa() {
  print -P "\n${CLR_HDR}path${CLR_RESET}"
  print -l -- ${(s/:/)PATH} | while read -r p; do
    print -P " ${CLR_NAME}${p}${CLR_RESET}"
  done
  echo
}

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

alias grep='grep --color=auto'
has bat && alias cat='bat -P --color=auto'

alias src='source ~/.zshrc'

alias c='clear'

cc() {
  jobs -p | xargs -r kill 2>/dev/null
  print -n $'\C-u'
  clear
  printf '\e[3J'
  printf '\e[H'
}

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
