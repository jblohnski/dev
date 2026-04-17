#!/bin/zsh
# dev-cmd: alias=macsm-anlyz name=macsm-anlyz group=audit run=user legend=hide desc="Analyze macsm watch run artifacts and summarize diffs"

# macsm_analyze.sh
# Analyze a macsm.sh run directory and summarize:
#  - which change events occurred
#  - which prefs/files changed (hash diffs)
#  - which keys likely changed (filtered diffs)
#  - which processes likely wrote prefs (fs_usage + log window)
#
# Usage:
#   ./macsm_analyze.sh /path/to/ua-watch/<run-timestamp>
#   ./macsm_analyze.sh /path/to/ua-watch/<run-timestamp>/change-YYYYMMDD-HHMMSS
#
# Output:
#   Prints to stdout and writes summary files under <run>/analysis/

set -euo pipefail

print() { /bin/echo "$@"; }
die() { print "ERROR: $*" >&2; exit 1; }

TARGET="${1:-}"
[[ -n "$TARGET" ]] || die "Provide a run dir or a change dir path."

# Normalize to RUN_DIR (the directory that contains fs_usage.filtered.txt and change-* dirs)
if [[ -d "$TARGET" && "$(basename "$TARGET")" == change-* ]]; then
  RUN_DIR="$(cd "$TARGET/.." && pwd)"
  ONLY_CHANGE="$(cd "$TARGET" && pwd)"
elif [[ -d "$TARGET" ]]; then
  RUN_DIR="$(cd "$TARGET" && pwd)"
  ONLY_CHANGE=""
else
  die "Not a directory: $TARGET"
fi

FSU="$RUN_DIR/fs_usage.filtered.txt"
STREAM_UA="$RUN_DIR/stream.accessibility.txt"
STREAM_AU="$RUN_DIR/stream.audio.txt"

AN_DIR="$RUN_DIR/analysis"
mkdir -p "$AN_DIR"

# Gather change dirs
typeset -a CHANGE_DIRS
if [[ -n "${ONLY_CHANGE:-}" ]]; then
  CHANGE_DIRS=("$ONLY_CHANGE")
else
  CHANGE_DIRS=("$RUN_DIR"/change-*)
fi

# If no changes captured yet
if (( ${#CHANGE_DIRS[@]} == 1 )) && [[ ! -d "${CHANGE_DIRS[1]}" ]]; then
  print "No change-* directories found under:"
  print "  $RUN_DIR"
  exit 0
fi

# Keyword filters for likely relevant changes
KW='CloseView|Zoom|Magnif|magnif|universalaccess|trackpad|ThreeFinger|gesture|rect|rectangle|cursor|pointer|accessib|AX|voice|dictat|speech|coreaudio|audio|volume|mute|beep'

# Helper: extract timestamp from change dir name change-YYYYMMDD-HHMMSS
chg_ts() {
  local b
  b="$(basename "$1")"
  print "${b#change-}"
}

# Helper: pretty print a header
hdr() {
  print ""
  print "================================================================================"
  print "$*"
  print "================================================================================"
}

# Helper: summarize a diff file with keyword filter + cap
summarize_diff_file() {
  local f="$1" cap="${2:-200}"
  [[ -f "$f" ]] || return 0
  egrep -n "$KW" "$f" 2>/dev/null | head -n "$cap" || true
}

# Helper: attempt to find fs_usage lines near a wall-clock time (HH:MM:SS)
fsu_near_time() {
  local hhmmss="$1" before="${2:-2}" after="${3:-4}"

  [[ -f "$FSU" ]] || return 0

  # fs_usage timestamps look like: "03:16:11.123456 ..."
  # We search +/- a few seconds by matching the HH:MM:SS prefix range crudely.
  # For simplicity: show exact second plus adjacent seconds (before/after).
  local hh="${hhmmss%%:*}"
  local rest="${hhmmss#*:}"
  local mm="${rest%%:*}"
  local ss="${hhmmss##*:}"

  # Build a small list of second strings, zero-padded.
  typeset -a secs
  integer i
  for (( i = -before; i <= after; i++ )); do
    integer s=$((10#$ss + i))
    (( s < 0 )) && continue
    (( s > 59 )) && continue
    secs+=("$(printf "%02d" "$s")")
  done

  local re="^$hh:$mm:($(IFS='|'; print "${secs[*]}"))\\."
  egrep -n "$re" "$FSU" | head -n 220 || true
}

# Helper: best-effort: pull HH:MM:SS from CHANGE_DETECTED line in defaults snapshot header (iso)
# We use the change dir timestamp (local) instead, because defaults snapshot doesn't include the trigger time.
hhmmss_from_change_dir() {
  local ts="$1" # YYYYMMDD-HHMMSS
  print "${ts#*-}" | sed 's/\(..\)\(..\)\(..\)/\1:\2:\3/'
}

# Produce a run index
hdr "RUN SUMMARY"
print "RUN_DIR: $RUN_DIR"
print "Changes found: ${#CHANGE_DIRS[@]}"
print "fs_usage: $([[ -f "$FSU" ]] && print "present" || print "missing")"
print "log streams: UA=$([[ -f "$STREAM_UA" ]] && print "present" || print "missing"), audio=$([[ -f "$STREAM_AU" ]] && print "present" || print "missing")"

# Save a machine-readable index
INDEX="$AN_DIR/index.txt"
: > "$INDEX"
for d in "${CHANGE_DIRS[@]}"; do
  [[ -d "$d" ]] || continue
  print "$(basename "$d")" >> "$INDEX"
done

# Summarize each change
OUT="$AN_DIR/summary.txt"
: > "$OUT"

for d in "${CHANGE_DIRS[@]}"; do
  [[ -d "$d" ]] || continue
  c="$(basename "$d")"
  ts="$(chg_ts "$d")"
  hhmmss="$(hhmmss_from_change_dir "$ts")"

  {
    hdr "CHANGE: $c"
    print "Path: $d"
    print "Approx time: $hhmmss (local)"
    print ""

    if [[ -f "$d/diff.hashes.txt" ]]; then
      print "== diff.hashes.txt (which files changed) =="
      sed -n '1,120p' "$d/diff.hashes.txt" || true
      print ""
    fi

    if [[ -f "$d/diff.defaults.txt" ]]; then
      print "== diff.defaults.txt (keyword hits) =="
      summarize_diff_file "$d/diff.defaults.txt" 200
      print ""
    fi

    # Any other diff.* files (plist dump diffs)
    typeset -a diffs
    diffs=("$d"/diff.*.txt)
    if (( ${#diffs[@]} > 0 )) && [[ -f "${diffs[1]}" ]]; then
      print "== diff.*.txt (plist dump diffs; keyword hits) =="
      integer shown=0
      for f in "${diffs[@]}"; do
        [[ -f "$f" ]] || continue
        # Only print files that actually have keyword hits, to reduce noise
        if egrep -q "$KW" "$f" 2>/dev/null; then
          print "-- $(basename "$f") --"
          summarize_diff_file "$f" 80
          print ""
          shown=$((shown + 1))
        fi
        (( shown >= 10 )) && break
      done
      (( shown == 0 )) && print "(no keyword hits in plist diffs)"
      print ""
    fi

    if [[ -f "$d/logshow.window.txt" ]]; then
      print "== logshow.window.txt (keyword hits) =="
      egrep -n "cfprefsd|universalaccessd|System Settings|ControlCenter|CloseView|zoom|universalaccess|trackpad|gesture|coreaudiod|volume|mute|dictat|speech" \
        "$d/logshow.window.txt" 2>/dev/null | tail -n 220 || true
      print ""
    fi

    if [[ -f "$FSU" ]]; then
      print "== fs_usage near $hhmmss (who wrote prefs) =="
      fsu_near_time "$hhmmss" 2 4
      print ""
      print "== fs_usage (pref writes anywhere; last 120 matches) =="
      egrep -n "com\.apple\.universalaccess|AppleMultitouchTrackpad|\.GlobalPreferences|Library/Preferences/" \
        "$FSU" 2>/dev/null | tail -n 120 || true
      print ""
    fi

  } | tee -a "$OUT"
done

# Also emit a concise "top writers" summary from fs_usage + log streams
TOP="$AN_DIR/top_writers.txt"
: > "$TOP"

if [[ -f "$FSU" ]]; then
  {
    hdr "TOP WRITERS (fs_usage filtered)"
    # fs_usage line often contains process name at start; we extract first field token-ish.
    # This is best-effort; output format can vary by macOS.
    awk '
      { p=$1; gsub(/[[:space:]]+/, "", p); if (p ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\./) { p=$2 }
        if (p != "") counts[p]++
      }
      END { for (k in counts) print counts[k], k }
    ' "$FSU" 2>/dev/null | sort -nr | head -n 30
    print ""
  } | tee "$TOP"
fi

print ""
print "Wrote:"
print "  $AN_DIR/index.txt"
print "  $AN_DIR/summary.txt"
[[ -f "$TOP" ]] && print "  $AN_DIR/top_writers.txt" || true
