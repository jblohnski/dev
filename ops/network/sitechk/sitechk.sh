#!/usr/bin/env bash
# dev-cmd: alias=site name=sitechk group=net run=user desc="Check DNS TLS HTTP"
# check_site_identity.sh
#
# Purpose:
#   Verify a site's DNS resolution, TLS certificate, HTTP response headers,
#   and optionally render a concise summary suitable for auditing.
#
# Usage:
#   ./check_site_identity.sh kagi.com
#   ./check_site_identity.sh https://kagi.com
#
# Notes:
#   - Works on macOS and Linux if dig, openssl, curl, and either whois or host exist.
#   - Produces simple component outputs plus an aggregate assessment.
#   - Good fit for dropping into your dev/audit tooling.

set -euo pipefail

PROG="${0##*/}"
TMPDIR_ROOT="${TMPDIR:-/tmp}"
WORKDIR="$(mktemp -d "${TMPDIR_ROOT%/}/sitecheck.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

log()  { printf '%s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

need_cmds=(dig openssl curl awk sed grep)
for c in "${need_cmds[@]}"; do
  have "$c" || die "required command not found: $c"
done

input="${1:-}"
[[ -n "$input" ]] || die "usage: $PROG <domain-or-url>"

normalize_host() {
  local s="$1"
  s="${s#http://}"
  s="${s#https://}"
  s="${s%%/*}"
  s="${s%%\?*}"
  s="${s%%#*}"
  printf '%s\n' "$s"
}

HOST="$(normalize_host "$input")"
[[ -n "$HOST" ]] || die "could not parse host from input: $input"

OUT_DNS_A="$WORKDIR/dns_a.txt"
OUT_DNS_AAAA="$WORKDIR/dns_aaaa.txt"
OUT_WHOIS="$WORKDIR/whois.txt"
OUT_TLS_RAW="$WORKDIR/tls_raw.txt"
OUT_TLS_CERT="$WORKDIR/tls_cert.txt"
OUT_HEADERS="$WORKDIR/headers.txt"
OUT_SUMMARY="$WORKDIR/summary.txt"

section() {
  printf '\n== %s ==\n' "$1"
}

run_dns() {
  section "DNS"
  dig "$HOST" A +short | sed '/^$/d' | tee "$OUT_DNS_A"
  dig "$HOST" AAAA +short | sed '/^$/d' | tee "$OUT_DNS_AAAA"

  local first_ip=""
  first_ip="$( { cat "$OUT_DNS_A" "$OUT_DNS_AAAA" 2>/dev/null || true; } | head -n1 )"

  if [[ -n "$first_ip" ]]; then
    printf '\nFirst resolved IP: %s\n' "$first_ip"
    if have whois; then
      whois "$first_ip" >"$OUT_WHOIS" 2>/dev/null || true
      awk '
        BEGIN{IGNORECASE=1}
        /OrgName:|org-name:|Organization:|owner:|descr:|netname:/ {
          print
        }
      ' "$OUT_WHOIS" | head -n 12
    elif have host; then
      host "$first_ip" | tee "$OUT_WHOIS" || true
    else
      printf 'whois/host not available; skipping ownership hint\n'
    fi
  else
    printf 'No A/AAAA records resolved\n'
  fi
}

run_tls() {
  section "TLS CERTIFICATE"
  if echo | openssl s_client -connect "${HOST}:443" -servername "$HOST" >"$OUT_TLS_RAW" 2>/dev/null; then
    awk '
      /BEGIN CERTIFICATE/,/END CERTIFICATE/ { print }
    ' "$OUT_TLS_RAW" > "$OUT_TLS_CERT"

    if [[ -s "$OUT_TLS_CERT" ]]; then
      openssl x509 -in "$OUT_TLS_CERT" -noout \
        -subject -issuer -dates -ext subjectAltName 2>/dev/null \
        | sed 's/^/  /'
    else
      printf '  unable to extract certificate\n'
    fi
  else
    printf '  openssl s_client connection failed\n'
  fi
}

run_http() {
  section "HTTP HEADERS"
  curl -sSI --max-time 15 "https://${HOST}/" | tee "$OUT_HEADERS"
}

extract_tls_field() {
  local key="$1"
  awk -F= -v k="$key" '
    $1 ~ k { sub(/^[^=]*=/,""); print; exit }
  ' "$OUT_TLS_CERT_INFO"
}

summarize() {
  local tls_info="$WORKDIR/tls_info.txt"
  OUT_TLS_CERT_INFO="$tls_info"

  if [[ -s "$OUT_TLS_CERT" ]]; then
    openssl x509 -in "$OUT_TLS_CERT" -noout \
      -subject -issuer -dates -ext subjectAltName >"$tls_info" 2>/dev/null || true
  else
    : >"$tls_info"
  fi

  local a_count aaaa_count issuer subject san http_status server_hdr sts_hdr
  a_count="$(grep -c . "$OUT_DNS_A" 2>/dev/null || true)"
  aaaa_count="$(grep -c . "$OUT_DNS_AAAA" 2>/dev/null || true)"
  issuer="$(awk -F= '/^issuer=/{sub(/^issuer=/,""); print; exit}' "$tls_info" 2>/dev/null || true)"
  subject="$(awk -F= '/^subject=/{sub(/^subject=/,""); print; exit}' "$tls_info" 2>/dev/null || true)"
  san="$(awk '
    BEGIN{capture=0}
    /X509v3 Subject Alternative Name/ {capture=1; next}
    capture && NF {gsub(/^[[:space:]]+/,""); print; exit}
  ' "$tls_info" 2>/dev/null || true)"
  http_status="$(awk 'toupper($1) ~ /^HTTP\// {print $2; exit}' "$OUT_HEADERS" 2>/dev/null || true)"
  server_hdr="$(awk 'BEGIN{IGNORECASE=1} /^server:/ {sub(/\r$/,""); print substr($0,9); exit}' "$OUT_HEADERS" 2>/dev/null || true)"
  sts_hdr="$(awk 'BEGIN{IGNORECASE=1} /^strict-transport-security:/ {print "present"; found=1; exit} END{if(!found) print "absent"}' "$OUT_HEADERS" 2>/dev/null || true)"

  local pass_dns="FAIL" pass_tls_subject="FAIL" pass_http="FAIL"
  [[ "$a_count" -gt 0 || "$aaaa_count" -gt 0 ]] && pass_dns="PASS"
  printf '%s\n' "$subject" | grep -Eq "(CN[[:space:]]*=[[:space:]]*)?${HOST//./\\.}" && pass_tls_subject="PASS"
  [[ "$http_status" =~ ^(200|301|302|307|308)$ ]] && pass_http="PASS"

  {
    section "AGGREGATE SUMMARY"
    printf 'Target host: %s\n' "$HOST"
    printf 'DNS records present: %s (A=%s AAAA=%s)\n' "$pass_dns" "$a_count" "$aaaa_count"
    printf 'TLS subject matches host: %s\n' "$pass_tls_subject"
    printf 'HTTP status acceptable: %s (status=%s)\n' "$pass_http" "${http_status:-unknown}"
    printf 'Server header: %s\n' "${server_hdr:-unknown}"
    printf 'HSTS: %s\n' "$sts_hdr"
    printf 'Certificate subject: %s\n' "${subject:-unknown}"
    printf 'Certificate issuer: %s\n' "${issuer:-unknown}"
    printf 'Certificate SAN: %s\n' "${san:-unknown}"

    local overall="REVIEW"
    if [[ "$pass_dns" == "PASS" && "$pass_tls_subject" == "PASS" && "$pass_http" == "PASS" ]]; then
      overall="LIKELY LEGITIMATE ENDPOINT"
    else
      overall="NEEDS MANUAL REVIEW"
    fi
    printf 'Overall assessment: %s\n' "$overall"
  } | tee "$OUT_SUMMARY"
}

emit_json() {
  local json="$WORKDIR/result.json"
  local dns_a dns_aaaa status server assessment
  dns_a="$(tr '\n' ',' < "$OUT_DNS_A" 2>/dev/null | sed 's/,$//')"
  dns_aaaa="$(tr '\n' ',' < "$OUT_DNS_AAAA" 2>/dev/null | sed 's/,$//')"
  status="$(awk 'toupper($1) ~ /^HTTP\// {print $2; exit}' "$OUT_HEADERS" 2>/dev/null || true)"
  server="$(awk 'BEGIN{IGNORECASE=1} /^server:/ {sub(/\r$/,""); print substr($0,9); exit}' "$OUT_HEADERS" 2>/dev/null || true)"
  assessment="$(awk -F': ' '/^Overall assessment:/ {print $2; exit}' "$OUT_SUMMARY" 2>/dev/null || true)"

  cat > "$json" <<EOF
{
  "host": "$(printf '%s' "$HOST" | sed 's/"/\\"/g')",
  "dns": {
    "a": [$(awk 'NF{printf "%s\"%s\"", (n++?", ":""), $0}' "$OUT_DNS_A" 2>/dev/null)],
    "aaaa": [$(awk 'NF{printf "%s\"%s\"", (n++?", ":""), $0}' "$OUT_DNS_AAAA" 2>/dev/null)]
  },
  "http": {
    "status": "$(printf '%s' "${status:-}" | sed 's/"/\\"/g')",
    "server": "$(printf '%s' "${server:-}" | sed 's/"/\\"/g')"
  },
  "assessment": "$(printf '%s' "${assessment:-}" | sed 's/"/\\"/g')"
}
EOF

  section "JSON"
  cat "$json"
}

run_dns
run_tls
run_http
summarize
emit_json
