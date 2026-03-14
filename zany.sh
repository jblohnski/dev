#!/usr/bin/env bash
set -euo pipefail

LOGDIR="${1:-$HOME/dev/zlogs}"

if [ ! -d "$LOGDIR" ]; then
    echo "Log directory not found: $LOGDIR"
    exit 1
fi

echo
echo "================================="
echo "Zeek Network Activity Report"
echo "Logs: $LOGDIR"
echo "================================="
echo

echo "Top Domains Queried"
echo "-------------------"
rg -N '^[^#]' "$LOGDIR/dns.log" \
| cut -f10 \
| sort | uniq -c | sort -nr | head -20
echo

echo "Top TLS Servers (SNI)"
echo "---------------------"
rg -N '^[^#]' "$LOGDIR/ssl.log" \
| cut -f9 \
| sort | uniq -c | sort -nr | head -20
echo

echo "Top External Destination IPs"
echo "----------------------------"
rg -N '^[^#]' "$LOGDIR/conn.log" \
| cut -f6 \
| grep -Ev '^(192\.168|10\.|172\.(1[6-9]|2[0-9]|3[0-1]))' \
| sort | uniq -c | sort -nr | head -20
echo

echo "Top Internal Talkers"
echo "--------------------"
rg -N '^[^#]' "$LOGDIR/conn.log" \
| cut -f3 \
| grep '^192\.168' \
| sort | uniq -c | sort -nr | head -10
echo

echo "Large Outbound Transfers (>10MB)"
echo "--------------------------------"
rg -N '^[^#]' "$LOGDIR/conn.log" \
| awk -F'\t' '$9 > 10000000 {print $3 " -> " $6 " bytes:" $9}' \
| head
echo

echo "Unique External IPs Observed"
echo "----------------------------"
rg -I -o '\b[0-9]{1,3}(\.[0-9]{1,3}){3}\b' "$LOGDIR"/*.log \
| sed 's/.*://' \
| grep -Ev '^(192\.168|224\.|239\.|255\.)' \
| sort -u \
| head -50
echo

echo "================================="
echo "Report complete"
echo "================================="
