#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:-./current}"
OUTFILE="$OUTDIR/signing.log"

mkdir -p "$OUTDIR"

echo "[signing] verifying core system binaries (summary mode)..."

# Keep this intentionally small + high-signal
TARGETS=(
  "/sbin/launchd"
  "/usr/libexec/amfid"
  "/usr/libexec/trustd"
  "/usr/libexec/syspolicyd"
  "/usr/libexec/logd"
  "/usr/libexec/UserEventAgent"
  "/usr/bin/codesign"
  "/usr/bin/security"
)

TOTAL=0
BAD=0

{
  echo "=== CODE SIGNATURE VERIFICATION ==="
  echo "Generated: $(date)"
  echo
} > "$OUTFILE"

for f in "${TARGETS[@]}"; do
  if [[ ! -e "$f" ]]; then
    continue
  fi

  ((TOTAL++)) || true

  SIG="$(codesign -dv --verbose=4 "$f" 2>&1 || true)"

  {
    echo "---- $f ----"
    echo "$SIG"
    echo
  } >> "$OUTFILE"

  # Suspicion conditions:
  #  - codesign error
  #  - missing authority chain
  #  - not Apple signed
  if grep -qi "code object is not signed" <<< "$SIG" \
     || grep -qi "invalid" <<< "$SIG" \
     || ! grep -q "Authority=Apple" <<< "$SIG"
  then
    ((BAD++)) || true
    echo "[sus] signing issue: $f"
  fi
done

echo "[signing] checked: $TOTAL"

if [[ "$BAD" -gt 0 ]]; then
  echo "[signing] issues detected: $BAD"
else
  echo "[signing] all verified Apple-signed"
fi
