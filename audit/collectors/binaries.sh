#!/usr/bin/env bash
# dev-cmd: alias=binaries name=Binaries group=audit run=user legend=hide desc="Collect executable inventory and suspicious unsigned binaries"

set -euo pipefail

OUTDIR="${1:-./current}"
OUTFILE="$OUTDIR/binaries.log"

mkdir -p "$OUTDIR"

TMP_ALL="$(mktemp)"
TMP_SUS="$(mktemp)"

# Paths most likely to contain user / 3rd-party executables
SCAN_PATHS=(
  "/usr/local/bin"
  "/opt"
  "$HOME/bin"
  "$HOME/.local/bin"
)

# Collect executables
for p in "${SCAN_PATHS[@]}"; do
  if [[ -d "$p" ]]; then
    find "$p" -type f -perm -111 2>/dev/null >> "$TMP_ALL" || true
  fi
done

# De-dup
sort -u "$TMP_ALL" > "$TMP_ALL.sorted"
mv "$TMP_ALL.sorted" "$TMP_ALL"

TOTAL=0
UNSIGNED=0
ADHOC=0

{
  echo "=== EXECUTABLE INVENTORY (high-signal) ==="
  echo "Generated: $(date)"
  echo "Scan paths:"
  printf "  - %s\n" "${SCAN_PATHS[@]}"
  echo
} > "$OUTFILE"

while IFS= read -r f; do
  ((TOTAL++)) || true

  # `codesign -dv` prints to stderr; capture and then keep only a small set of lines
  RAW="$(codesign -dv --verbose=4 "$f" 2>&1 || true)"
  SIG="$(printf '%s\n' "$RAW" | egrep '^(Executable=|Identifier=|Format=|CodeDirectory|Signature|Authority=|TeamIdentifier=|Timestamp=|CDHash=)' || true)"

  {
    echo "---- $f ----"
    if [[ -n "$SIG" ]]; then
      echo "$SIG"
    else
      # non-code objects (scripts, etc) often produce an error; keep a one-liner
      echo "$RAW" | head -n 1
    fi
    echo
  } >> "$OUTFILE"

  # Suspicious heuristics (high signal):
  #  - explicitly unsigned
  #  - ad-hoc signatures
  if grep -qi "code object is not signed at all" <<< "$RAW"; then
    ((UNSIGNED++)) || true
    echo "$f" >> "$TMP_SUS"
  elif grep -q "Authority=Ad Hoc" <<< "$RAW"; then
    ((ADHOC++)) || true
    echo "$f" >> "$TMP_SUS"
  fi
done < "$TMP_ALL"

SUS=$((UNSIGNED + ADHOC))

# Summary to stdout (single line)
if [[ "$SUS" -gt 0 ]]; then
  echo "[binaries] scanned=$TOTAL suspicious=$SUS (unsigned=$UNSIGNED adhoc=$ADHOC)"
else
  echo "[binaries] scanned=$TOTAL suspicious=0"
fi

# Persist suspect list into log footer
if [[ -s "$TMP_SUS" ]]; then
  {
    echo
    echo "=== SUSPICIOUS BINARIES (unsigned or ad-hoc) ==="
    sort -u "$TMP_SUS"
  } >> "$OUTFILE"
fi

rm -f "$TMP_ALL" "$TMP_SUS"
