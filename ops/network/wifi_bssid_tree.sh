#!/usr/bin/env zsh
# dev-cmd: alias=wbt name=wifi-bssid group=net run=user desc="Group Wi-Fi BSSIDs"
#
# dev:network:wifi
# BSSID → SSID association tree
#

set -euo pipefail

AIRPORT="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
SYSTEM_PROFILER="/usr/sbin/system_profiler"

[[ -x "$SYSTEM_PROFILER" || -x "$AIRPORT" ]] || {
 echo "No supported Wi-Fi scan backend found"
 exit 1
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

backend=""
scan_has_sections=0

if [[ -x "$SYSTEM_PROFILER" ]]; then
 "$SYSTEM_PROFILER" SPAirPortDataType > "$tmp" 2>/dev/null || true

 if grep -qE 'Current Network Information:|Other Local Wi-Fi Networks:' "$tmp"; then
    backend="system_profiler"
    scan_has_sections=1
 elif grep -q 'Status: Network Service Inactive' "$tmp"; then
    echo "Wi-Fi service appears inactive"
    exit 1
 fi
fi

if [[ -z "$backend" && -x "$AIRPORT" ]]; then
 "$AIRPORT" -s > "$tmp" 2>/dev/null || {
    echo "Wi-Fi scan failed"
    exit 1
 }

 if grep -qiE '^ *SSID +BSSID|([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}' "$tmp"; then
    backend="airport"
 fi
fi

if [[ -z "$backend" ]]; then
 echo "macOS did not expose Wi-Fi scan results to this script"
 echo "sudo usually does not fix this on current macOS"
 echo "Use a signed app with Location permission, or fall back to a GUI tool"
 exit 1
fi

if [[ "$backend" == "system_profiler" ]]; then
awk '
function trim(value) {
 sub(/^[[:space:]]+/, "", value)
 sub(/[[:space:]]+$/, "", value)
 return value
}

function flush_record(    key, entry) {
 if (ssid == "" || bssid == "") {
    return
 }

 key=bssid
 entry=sprintf("%s (%sdBm ch%s)", ssid, signal == "" ? "?" : signal, channel == "" ? "?" : channel)

 if (!(key in seen)) {
    seen[key]=1
    order[++n]=key
 }

 if (!(entry_seen[key SUBSEP entry])) {
    entry_seen[key SUBSEP entry]=1
    data[key]=data[key] entry "|"
 }
}

{
 line=$0

 if (line ~ /^[[:space:]]+Current Network Information:$/) {
    flush_record()
    section="current"
    ssid=""
    bssid=""
    channel=""
    signal=""
    next
 }

 if (line ~ /^[[:space:]]+Other Local Wi-Fi Networks:$/) {
    flush_record()
    section="other"
    ssid=""
    bssid=""
    channel=""
    signal=""
    next
 }

 if (section == "") {
    next
 }

 if (line ~ /^[[:space:]]+[^:]+:$/ && line !~ /(Current Network Information|Other Local Wi-Fi Networks):$/) {
    flush_record()
    ssid=trim(substr(line, 1, length(line) - 1))
    bssid=""
    channel=""
    signal=""
    next
 }

 if (line ~ /^[[:space:]]+BSSID:/) {
    sub(/^[[:space:]]+BSSID:[[:space:]]*/, "", line)
    bssid=trim(line)
    next
 }

 if (line ~ /^[[:space:]]+Channel:/) {
    sub(/^[[:space:]]+Channel:[[:space:]]*/, "", line)
    channel=trim(line)
    next
 }

 if (line ~ /^[[:space:]]+Signal \/ Noise:/) {
    if (match(line, /-?[0-9]+[[:space:]]dBm/)) {
       signal=substr(line, RSTART, RLENGTH)
       sub(/[[:space:]]dBm$/, "", signal)
    }
    next
 }
}

END {
 flush_record()

 if (n == 0) {
    print "No Wi-Fi networks found"
    exit
 }

 for (i=1; i<=n; i++) {
    b=order[i]
    printf "%s\n", b
    split(data[b], arr, "|")
    for (j in arr) {
       if (arr[j] != "") {
          printf "  └─ %s\n", arr[j]
       }
    }
    print ""
 }
}
' "$tmp"
else
awk '
function trim(value) {
 sub(/^[[:space:]]+/, "", value)
 sub(/[[:space:]]+$/, "", value)
 return value
}

function is_bssid(value) {
 return value ~ /^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$/
}

{
 if ($0 ~ /^WARNING:/ || $0 ~ /^[[:space:]]*$/) {
    next
 }

 bssid_idx=0

 for (i=1; i<=NF; i++) {
    if (is_bssid($i)) {
       bssid_idx=i
       break
    }
 }

 if (bssid_idx == 0) {
    next
 }

 ssid=""
 for (i=1; i<bssid_idx; i++) {
    ssid = ssid (i == 1 ? "" : " ") $i
 }

 ssid=trim(ssid)
 if (ssid == "") {
    ssid="<hidden>"
 }

 bssid=$bssid_idx
 rssi=$(bssid_idx + 1)
 chan=$(bssid_idx + 2)

 if (rssi == "" || chan == "") {
    next
 }

 key=bssid

 if (!(key in seen)) {
    seen[key]=1
    order[++n]=key
 }

 data[key]=data[key] sprintf("%s (%sdBm ch%s)|", ssid, rssi, chan)
}

END {
 if (n == 0) {
    print "No Wi-Fi networks found"
    exit
 }

 for(i=1;i<=n;i++) {

    b=order[i]

    printf "%s\n", b

    split(data[b], arr, "|")

    for(j in arr)
    if(arr[j]!="")
       printf "  └─ %s\n", arr[j]

       print ""
 }
}
' "$tmp"
fi
