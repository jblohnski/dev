#!/usr/bin/env bash
# @desc: Collect trust chain and SIP-related anomaly signals
# @tags: audit collector trust sip
# @run: user

set -euo pipefail

OUTDIR="${1:-./current}"
mkdir -p "$OUTDIR"

# Write anomalies to a dedicated file for the analyzer
SUMMARY_OUT="$OUTDIR/trust_summary.txt"
: > "$SUMMARY_OUT"

SUS=0

# --- collect raw data quietly ---
codesign -dv --verbose=4 /usr/libexec/amfid > "$OUTDIR/amfid_codesign.txt" 2>&1 || true
codesign -dv --verbose=4 /usr/libexec/trustd > "$OUTDIR/trustd_codesign.txt" 2>&1 || true
codesign -dv --verbose=4 /usr/libexec/syspolicyd > "$OUTDIR/syspolicyd_codesign.txt" 2>&1 || true

csrutil status > "$OUTDIR/sip_status.txt" 2>&1 || true
kmutil showloaded > "$OUTDIR/kmutil_loaded.txt" 2>&1 || true

# --- analyze for suspicious conditions ---

note_sus() {
  echo "[sus] $*" >> "$SUMMARY_OUT"
  ((SUS++)) || true
}

check_codesign() {
  local target="$1"
  local detail_file="$2"
  local label="$3"

  # Avoid relying on Authority=Apple; some Apple binaries report Authority=(unavailable).
  if ! codesign --verify --verbose=2 "$target" >/dev/null 2>&1; then
    note_sus "trust anomaly: $label failed codesign verification"
    return
  fi

  if grep -qi "code object is not signed" "$detail_file" \
     || grep -qi "invalid" "$detail_file"
  then
    note_sus "trust anomaly: $label shows invalid signature metadata"
  fi
}

check_codesign "/usr/libexec/amfid" "$OUTDIR/amfid_codesign.txt" "amfid"
check_codesign "/usr/libexec/trustd" "$OUTDIR/trustd_codesign.txt" "trustd"
check_codesign "/usr/libexec/syspolicyd" "$OUTDIR/syspolicyd_codesign.txt" "syspolicyd"

# SIP check
if ! grep -qi "enabled" "$OUTDIR/sip_status.txt"; then
  note_sus "SIP is NOT enabled"
fi

# Non-Apple kernel extension check
if grep -v "com.apple" "$OUTDIR/kmutil_loaded.txt" | grep -q "bundle"; then
  note_sus "non-Apple kernel extension detected"
fi

# Summary (stdout single line)
if [[ "$SUS" -eq 0 ]]; then
  echo "[trust] OK"
else
  echo "[trust] issues: $SUS (see trust_summary.txt)"
fi
