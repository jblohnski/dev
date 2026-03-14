#!/usr/bin/env bash
# @desc: Audit router/Wi-Fi security posture and exposure
# @tags: ops network security audit
# @run: user
# @alias: router
# @owner: firstparty
# router_harden_audit.sh
# Minimal LAN/Wi-Fi security audit helper
# macOS + Linux compatible

set -euo pipefail

RED="$(tput setaf 1)"
GRN="$(tput setaf 2)"
YEL="$(tput setaf 3)"
BLU="$(tput setaf 4)"
RST="$(tput sgr0)"
AIRPORT="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

echo "${BLU}== Router / Wi-Fi Hardening Audit ==${RST}"
echo

# -------------------------------------------------
# 1. Identify default gateway
# -------------------------------------------------
GW=$(ip route 2>/dev/null | awk '/default/ {print $3}' | head -1 || true)
if [ -z "${GW}" ]; then
  GW=$(route -n get default 2>/dev/null | awk '/gateway/ {print $2}' || true)
fi
if [ -z "${GW}" ]; then
  GW=$(netstat -rn -f inet 2>/dev/null | awk '$1 == "default" {print $2; exit}' || true)
fi

if [ -z "${GW}" ]; then
  echo "${RED}[-] Could not detect gateway${RST}"
else
  echo "${GRN}[+] Default gateway: ${GW}${RST}"
fi
echo

# -------------------------------------------------
# 2. ARP table inspection (MITM surface check)
# -------------------------------------------------
echo "${BLU}== ARP Table Snapshot ==${RST}"
arp -an || true
echo

# -------------------------------------------------
# 3. Check for duplicate MACs (simple detection)
# -------------------------------------------------
echo "${BLU}== Duplicate MAC Detection ==${RST}"
arp -an | awk '{print $4}' | sort | uniq -d | while read mac; do
  echo "${RED}[-] Duplicate MAC detected: $mac${RST}"
done
echo "${GRN}[+] MAC duplication scan complete${RST}"
echo

# -------------------------------------------------
# 4. DNS resolution sanity
# -------------------------------------------------
echo "${BLU}== DNS Resolver Check ==${RST}"
SCUTIL_DNS=$(scutil --dns 2>/dev/null | grep 'nameserver\[[0-9]*\]' || true)
if [ -n "$SCUTIL_DNS" ]; then
  echo "$SCUTIL_DNS"
else
  cat /etc/resolv.conf | grep nameserver || true
fi
echo

# -------------------------------------------------
# 5. Check open ports on gateway
# -------------------------------------------------
if [ -n "${GW}" ]; then
  echo "${BLU}== Gateway Port Scan (Top 1000 TCP) ==${RST}"
  nmap -Pn -T4 --top-ports 1000 "$GW" || echo "${YEL}[!] nmap not installed${RST}"
fi
echo

# -------------------------------------------------
# 6. Check Wi-Fi encryption (macOS only)
# -------------------------------------------------
if [ -x "${AIRPORT}" ]; then
  echo "${BLU}== Wi-Fi Security Info ==${RST}"
  WIFI_INFO=$("${AIRPORT}" -I 2>/dev/null | grep -E ' SSID|link auth|auth|BSSID|channel' || true)
  if [ -n "${WIFI_INFO}" ]; then
    echo "${WIFI_INFO}"
  else
    echo "${YEL}[!] Wi-Fi details unavailable${RST}"
  fi
fi
echo

# -------------------------------------------------
# 7. Passive MITM heuristic (quick)
# -------------------------------------------------
echo "${BLU}== Quick MITM Heuristic ==${RST}"
ping -c 3 "$GW" >/dev/null 2>&1 && echo "${GRN}[+] Gateway reachable${RST}"
echo "Monitor for ARP changes with: watch -n1 arp -an"
echo

echo "${BLU}== Manual Hardening Checklist ==${RST}"
cat <<EOF

Router Settings To Enforce:

[ ] WPA3-Personal (or WPA2-AES only, no TKIP)
[ ] Disable WPS
[ ] Disable UPnP (unless strictly required)
[ ] Disable remote admin
[ ] Change router admin password (random 16+ chars)
[ ] Separate SSIDs/VLANs:
      - trusted
      - IoT
      - guest
[ ] Enable client/AP isolation on guest + IoT
[ ] Enable automatic firmware updates
[ ] Use DNS over HTTPS (router-level if supported)

Optional:
[ ] Disable 2.4GHz if unnecessary
[ ] Disable legacy 802.11b
[ ] Reduce transmit power slightly (if dense environment)

EOF

echo "${GRN}Audit complete.${RST}"
