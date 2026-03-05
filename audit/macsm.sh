#!/bin/zsh
# macsm.sh
# macOS (zsh) watcher for:
#  - Accessibility Zoom / Universal Access (e.g., 3-finger rectangle magnifier behavior)
#  - Audio state (volume/mute)
#
# Captures:
#  - Baseline + per-change snapshots of defaults/prefs
#  - Best-effort plist dumps (plutil -p) + xml conversion for diffing
#  - Unified log streams (cfprefsd / universalaccessd / coreaudiod etc.)
#  - Optional fs_usage (sudo) filtered to who is writing prefs
#
# Output is written under $TMPDIR/ua-watch/<timestamp>/...

set -euo pipefail
setopt NULL_GLOB

RUN_ROOT="${TMPDIR:-/tmp}/ua-watch"
TS="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$RUN_ROOT/$TS"
mkdir -p "$RUN_DIR"

print() { /bin/echo "$@"; }
die() { print "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

need log
need defaults
need plutil
need shasum
need diff
need osascript
need system_profiler

iso_now() { date "+%Y-%m-%dT%H:%M:%S%z"; }

# --- Prefer patterns, expand safely (no "no matches found") ---
PREF_PATTERNS=(
  "$HOME/Library/Preferences/com.apple.universalaccess.plist"
  "$HOME/Library/Preferences/ByHost/com.apple.universalaccess.*.plist"
  "$HOME/Library/Preferences/.GlobalPreferences.plist"
  "$HOME/Library/Preferences/ByHost/.GlobalPreferences.*.plist"
  "$HOME/Library/Preferences/com.apple.AppleMultitouchTrackpad.plist"
  "$HOME/Library/Preferences/ByHost/com.apple.AppleMultitouchTrackpad.*.plist"
)

AUDIO_PREF_PATTERNS=(
  "$HOME/Library/Preferences/com.apple.sound.beep.plist"
  "$HOME/Library/Preferences/ByHost/com.apple.sound.beep.*.plist"
)

WATCH_FILES=()
for p in "${PREF_PATTERNS[@]}" "${AUDIO_PREF_PATTERNS[@]}"; do
  # ${~p} expands pattern stored in variable even if quoted in array
  for f in ${~p}; do
    [[ -f "$f" ]] && WATCH_FILES+=("$f")
  done
done
typeset -U WATCH_FILES

snapshot_defaults() {
  local out="$1"
  {
    print "=== SNAPSHOT @ $(iso_now) ==="
    print ""
    print "## com.apple.universalaccess (user)"
    defaults read com.apple.universalaccess 2>/dev/null || print "(no keys / domain missing)"
    print ""
    print "## com.apple.universalaccess (currentHost)"
    defaults -currentHost read com.apple.universalaccess 2>/dev/null || print "(no keys / domain missing)"
    print ""
    print "## NSGlobalDomain (-g) filtered (Zoom/UA/gesture-ish)"
    (defaults read -g 2>/dev/null | egrep -i "CloseView|UniversalAccess|Zoom|gesture|trackpad|magnif" || true)
    print ""
    print "## Trackpad domain filtered (if present)"
    (defaults read com.apple.AppleMultitouchTrackpad 2>/dev/null | egrep -i "ThreeFinger|TrackpadThreeFinger|Zoom|gesture|magnif" || true)
    (defaults -currentHost read com.apple.AppleMultitouchTrackpad 2>/dev/null | egrep -i "ThreeFinger|TrackpadThreeFinger|Zoom|gesture|magnif" || true)
    print ""
    print "## Audio quick state (AppleScript get volume settings)"
    print "Output volume: $(osascript -e 'output volume of (get volume settings)')"
    print "Input volume : $(osascript -e 'input volume of (get volume settings)')"
    print "Output muted : $(osascript -e 'output muted of (get volume settings)')"
  } > "$out"
}

snapshot_plists_dump() {
  local outdir="$1"
  mkdir -p "$outdir"

  for f in "${WATCH_FILES[@]}"; do
    [[ -f "$f" ]] || continue
    local base
    base="$(basename "$f")"

    # Always: print-tree dump. Works even with non-JSON-safe objects.
    plutil -p "$f" > "$outdir/$base.plutil_p.txt" 2> "$outdir/$base.plutil_p.err" || true

    # Best-effort: XML conversion for diffing (may still fail on some files)
    plutil -convert xml1 -o "$outdir/$base.xml" "$f" 2> "$outdir/$base.xml.err" || true
  done
}

hash_files() {
  local out="$1"
  : > "$out"
  for f in "${WATCH_FILES[@]}"; do
    [[ -f "$f" ]] || continue
    shasum -a 256 "$f" >> "$out"
  done
}

grab_logs_window() {
  local start="$1" end="$2" out="$3"

  # A practical set of processes frequently involved in UA pref changes or audio changes.
  # Keep it broad enough to catch real culprits.
  log show --style syslog --start "$start" --end "$end" \
    --predicate '(process == "cfprefsd" OR process == "universalaccessd" OR process CONTAINS[c] "System Settings" OR process == "ControlCenter" OR process == "coreaudiod" OR eventMessage CONTAINS[c] "universalaccess" OR eventMessage CONTAINS[c] "CloseView" OR eventMessage CONTAINS[c] "zoom")' \
    > "$out" 2>/dev/null || true
}

start_log_streams() {
  local out_access="$1" out_audio="$2"

  log stream --style syslog --level info \
    --predicate '(process == "cfprefsd" OR process == "universalaccessd" OR process CONTAINS[c] "System Settings" OR process == "ControlCenter" OR eventMessage CONTAINS[c] "universalaccess" OR eventMessage CONTAINS[c] "CloseView" OR eventMessage CONTAINS[c] "zoom")' \
    > "$out_access" 2>&1 &
  STREAM_PID_ACCESS=$!

  log stream --style syslog --level info \
    --predicate '(process == "coreaudiod" OR eventMessage CONTAINS[c] "volume" OR eventMessage CONTAINS[c] "mute")' \
    > "$out_audio" 2>&1 &
  STREAM_PID_AUDIO=$!
}

start_fs_usage() {
  local out="$1"
  print "Starting fs_usage (sudo). Enter password if prompted."
  # filesystem writes; filter for prefs paths + likely writers
  sudo fs_usage -w -f filesystem 2>/dev/null | \
    egrep -i 'Library/Preferences/|ByHost/|com\.apple\.universalaccess|AppleMultitouchTrackpad|\.GlobalPreferences\.plist|com\.apple\.sound\.beep|cfprefsd|universalaccessd|System Settings|ControlCenter|coreaudiod' \
    > "$out" 2>&1 &
  FS_PID=$!
}

cleanup() {
  set +e
  [[ "${STREAM_PID_ACCESS:-}" != "" ]] && kill "$STREAM_PID_ACCESS" >/dev/null 2>&1
  [[ "${STREAM_PID_AUDIO:-}"  != "" ]] && kill "$STREAM_PID_AUDIO"  >/dev/null 2>&1
  if [[ "${FS_PID:-}" != "" ]]; then
    sudo kill "$FS_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

# --- Start ---
print "Run dir: $RUN_DIR"
print "Watched files:"
if (( ${#WATCH_FILES[@]} == 0 )); then
  print "  (none matched; will still use defaults read + logs)"
else
  for f in "${WATCH_FILES[@]}"; do
    print "  - $f"
  done
fi
print ""

print "Writing baseline snapshots..."
snapshot_defaults "$RUN_DIR/baseline.defaults.txt"
snapshot_plists_dump "$RUN_DIR/baseline.plists.dump"
hash_files "$RUN_DIR/baseline.hashes.txt"

# One-time hardware-ish info (can be slow)
system_profiler SPAudioDataType > "$RUN_DIR/system_profiler.audio.txt" 2>/dev/null || true

print "Starting unified log streams..."
start_log_streams "$RUN_DIR/stream.accessibility.txt" "$RUN_DIR/stream.audio.txt"

# fs_usage is optional; if sudo fails, continue.
start_fs_usage "$RUN_DIR/fs_usage.filtered.txt" || true

print ""
print "Monitoring for changes. Reproduce the issue now (toggle Zoom gesture / rectangle style / audio)."
print "Press Ctrl+C to stop."
print ""

LAST_HASH="$RUN_DIR/baseline.hashes.txt"
ITER=0

while true; do
  sleep 2
  ITER=$((ITER + 1))

  CUR_HASH="$RUN_DIR/current.hashes.txt"
  hash_files "$CUR_HASH"

  if ! diff -q "$LAST_HASH" "$CUR_HASH" >/dev/null 2>&1; then
    CHG_TS="$(date +%Y%m%d-%H%M%S)"
    CHG_DIR="$RUN_DIR/change-$CHG_TS"
    mkdir -p "$CHG_DIR"

    print "CHANGE DETECTED @ $(iso_now)"
    cp "$CUR_HASH" "$CHG_DIR/hashes.txt"

    snapshot_defaults "$CHG_DIR/defaults.txt"
    snapshot_plists_dump "$CHG_DIR/plists.dump"

    # Diff defaults baseline vs current
    diff -u "$RUN_DIR/baseline.defaults.txt" "$CHG_DIR/defaults.txt" > "$CHG_DIR/diff.defaults.txt" || true

    # Diff plist dumps baseline vs current (plutil -p + xml files)
    if [[ -d "$RUN_DIR/baseline.plists.dump" ]]; then
      for cur in "$CHG_DIR/plists.dump/"*; do
        [[ -f "$cur" ]] || continue
        base="$RUN_DIR/baseline.plists.dump/$(basename "$cur")"
        if [[ -f "$base" ]]; then
          diff -u "$base" "$cur" > "$CHG_DIR/diff.$(basename "$cur").txt" || true
        fi
      done
    fi

    # Diff hashes for quick "which file changed"
    diff -u "$LAST_HASH" "$CUR_HASH" > "$CHG_DIR/diff.hashes.txt" || true

    # Capture a 2-minute log window centered around now (best-effort)
    START_WIN="$(date -v-60S "+%Y-%m-%d %H:%M:%S")"
    END_WIN="$(date -v+60S "+%Y-%m-%d %H:%M:%S")"
    grab_logs_window "$START_WIN" "$END_WIN" "$CHG_DIR/logshow.window.txt"

    # Update last hash to avoid firing repeatedly on same change
    cp "$CUR_HASH" "$LAST_HASH"

    print "  Saved: $CHG_DIR"
    print "  Key files:"
    print "    - diff.defaults.txt"
    print "    - diff.* (plist dump diffs)"
    print "    - logshow.window.txt"
    print "    - fs_usage.filtered.txt (in run root)"
    print ""
  fi

  if (( ITER % 30 == 0 )); then
    print "Still watching... $(iso_now)"
  fi
done
