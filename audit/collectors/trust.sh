#!/usr/bin/env bash
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
  local file="$1"
  local label="$2"

  if grep -qi "code object is not signed" "$file" \
     || grep -qi "invalid" "$file" \
     || ! grep -q "Authority=Apple" "$file"
  then
    note_sus "trust anomaly: $label not Apple-signed or invalid"
  fi
}

check_codesign "$OUTDIR/amfid_codesign.txt" "amfid"
check_codesign "$OUTDIR/trustd_codesign.txt" "trustd"
check_codesign "$OUTDIR/syspolicyd_codesign.txt" "syspolicyd"

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
