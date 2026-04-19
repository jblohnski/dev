#!/usr/bin/env bash
# dev-cmd: alias=sysclean name="System Clean" group=sys run=sudo desc="Aggressively clear macOS caches, browser cookies, temp files, and local web state"

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "sysclean.sh is macOS-only." >&2
  exit 1
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "sysclean.sh must run as root." >&2
  exit 1
fi

DRY_RUN=0
ASSUME_YES=0
INCLUDE_SYSTEM=1
INCLUDE_USER=1
INCLUDE_BROWSERS=1

usage() {
  cat <<'EOF'
Usage:
  sysclean.sh [--dry-run] [--yes] [--system-only|--user-only] [--no-browsers]

Options:
  --dry-run      Print the cleanup plan without deleting anything.
  --yes          Skip the destructive-action confirmation prompt.
  --system-only  Clean system-level cache/temp surfaces only.
  --user-only    Clean the invoking user's cache/browser surfaces only.
  --no-browsers  Leave browser cookies/history/web storage untouched.
  -h, --help     Show this help text.

Notes:
  - Targets the invoking sudo user when available.
  - Removes caches, temp files, cookies, history, and local website storage.
  - Does not remove saved passwords or bookmarks.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --yes)
      ASSUME_YES=1
      ;;
    --system-only)
      INCLUDE_SYSTEM=1
      INCLUDE_USER=0
      ;;
    --user-only)
      INCLUDE_SYSTEM=0
      INCLUDE_USER=1
      ;;
    --no-browsers)
      INCLUDE_BROWSERS=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

TARGET_USER="${SUDO_USER:-}"
TARGET_HOME=""
if [[ -n "$TARGET_USER" ]]; then
  TARGET_HOME="$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
fi
if [[ -z "$TARGET_HOME" && -d "${HOME:-}" && "${HOME:-}" != "/var/root" ]]; then
  TARGET_HOME="$HOME"
fi

if (( INCLUDE_USER )) && [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
  echo "Could not resolve a target user home for user-scope cleanup." >&2
  exit 1
fi

if (( ASSUME_YES == 0 )); then
  if [[ ! -t 0 ]]; then
    echo "Refusing destructive cleanup without --yes in a non-interactive session." >&2
    exit 1
  fi
  echo "This will aggressively remove caches, cookies, history, temp files, and website data."
  if (( INCLUDE_SYSTEM )); then
    echo "  - system-level caches and temp directories"
  fi
  if (( INCLUDE_USER )); then
    echo "  - user-level caches under: ${TARGET_HOME}"
  fi
  if (( INCLUDE_BROWSERS )); then
    echo "  - browser cookies, cache, and local web state"
  fi
  read -r -p "Continue? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Aborted."
      exit 1
      ;;
  esac
fi

shopt -s nullglob dotglob

actions=0
failures=0

note() {
  printf '%s\n' "$*"
}

run_rm() {
  local path="$1"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi
  (( actions += 1 ))
  if (( DRY_RUN )); then
    note "rm -rf $path"
    return 0
  fi
  if ! rm -rf -- "$path" 2>/dev/null; then
    (( failures += 1 ))
    note "warn: failed to remove $path"
  fi
}

clear_dir_contents() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  local entry
  for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    run_rm "$entry"
  done
}

wipe_paths() {
  local path
  for path in "$@"; do
    run_rm "$path"
  done
}

kill_browser_processes() {
  local proc
  local -a procs=(
    "Safari"
    "Safari Technology Preview"
    "Google Chrome"
    "Google Chrome Canary"
    "Chromium"
    "Brave Browser"
    "Microsoft Edge"
    "Arc"
    "Firefox"
    "LibreWolf"
    "WebKitNetworkProcess"
  )
  for proc in "${procs[@]}"; do
    if (( DRY_RUN )); then
      note "pkill -x $proc"
    else
      pkill -x "$proc" 2>/dev/null || true
    fi
  done
  (( DRY_RUN == 0 )) && sleep 1
}

clean_system_scope() {
  note "== system scope =="
  clear_dir_contents "/Library/Caches"
  clear_dir_contents "/private/var/tmp"
  clear_dir_contents "/private/tmp"

  local dir
  for dir in /private/var/folders/*/*/C /private/var/folders/*/*/T; do
    clear_dir_contents "$dir"
  done

  if (( DRY_RUN )); then
    note "dscacheutil -flushcache"
    note "killall -HUP mDNSResponder"
    note "qlmanage -r cache"
  else
    dscacheutil -flushcache 2>/dev/null || true
    killall -HUP mDNSResponder 2>/dev/null || true
    qlmanage -r cache >/dev/null 2>&1 || true
  fi
}

clean_user_scope() {
  local home_dir="$1"
  note "== user scope: $home_dir =="

  clear_dir_contents "$home_dir/Library/Caches"
  clear_dir_contents "$home_dir/Library/HTTPStorages"
  clear_dir_contents "$home_dir/Library/Saved Application State"
  clear_dir_contents "$home_dir/Library/Logs/DiagnosticReports"
  clear_dir_contents "$home_dir/.Trash"

  local dir
  for dir in "$home_dir/Library/Containers"/*/Data/Library/Caches; do
    clear_dir_contents "$dir"
  done
  for dir in "$home_dir/Library/Group Containers"/*/Library/Caches; do
    clear_dir_contents "$dir"
  done
  for dir in "$home_dir/Library/WebKit"/*/WebsiteData; do
    clear_dir_contents "$dir"
  done
  for dir in "$home_dir/Library/Containers"/*/Data/Library/WebKit/*/WebsiteData; do
    clear_dir_contents "$dir"
  done
}

clean_safari() {
  local home_dir="$1"
  note "== safari =="
  clear_dir_contents "$home_dir/Library/Caches/com.apple.Safari"
  clear_dir_contents "$home_dir/Library/Caches/com.apple.WebKit.Networking"
  clear_dir_contents "$home_dir/Library/Safari/Favicon Cache"
  clear_dir_contents "$home_dir/Library/Safari/LocalStorage"
  clear_dir_contents "$home_dir/Library/Safari/Databases"
  clear_dir_contents "$home_dir/Library/Containers/com.apple.Safari/Data/Library/Caches"
  clear_dir_contents "$home_dir/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData"
  clear_dir_contents "$home_dir/Library/Containers/com.apple.WebKit.Networking/Data/Library/Caches"
  wipe_paths \
    "$home_dir/Library/Cookies/Cookies.binarycookies" \
    "$home_dir/Library/Cookies/HSTS.plist" \
    "$home_dir/Library/Safari/History.db" \
    "$home_dir/Library/Safari/History.db-shm" \
    "$home_dir/Library/Safari/History.db-wal" \
    "$home_dir/Library/Safari/BrowserState.db" \
    "$home_dir/Library/Safari/BrowserState.db-shm" \
    "$home_dir/Library/Safari/BrowserState.db-wal" \
    "$home_dir/Library/Safari/LastSession.plist" \
    "$home_dir/Library/Safari/RecentlyClosedTabs.plist"
}

clean_chromium_family() {
  local base="$1"
  [[ -d "$base" ]] || return 0

  local profile
  for profile in "$base"/Default "$base"/Profile* "$base"/Guest\ Profile "$base"/System\ Profile; do
    [[ -d "$profile" ]] || continue
    clear_dir_contents "$profile/Cache"
    clear_dir_contents "$profile/Code Cache"
    clear_dir_contents "$profile/GPUCache"
    clear_dir_contents "$profile/DawnCache"
    clear_dir_contents "$profile/GrShaderCache"
    clear_dir_contents "$profile/Session Storage"
    clear_dir_contents "$profile/Local Storage"
    clear_dir_contents "$profile/IndexedDB"
    clear_dir_contents "$profile/File System"
    clear_dir_contents "$profile/blob_storage"
    clear_dir_contents "$profile/Service Worker/CacheStorage"
    clear_dir_contents "$profile/Storage"
    clear_dir_contents "$profile/Network"
    wipe_paths \
      "$profile/Cookies" \
      "$profile/Cookies-journal" \
      "$profile/History" \
      "$profile/History-journal" \
      "$profile/Visited Links"
  done
}

clean_firefox_family() {
  local base="$1"
  [[ -d "$base" ]] || return 0

  local profile
  for profile in "$base"/*; do
    [[ -d "$profile" ]] || continue
    clear_dir_contents "$profile/cache2"
    clear_dir_contents "$profile/startupCache"
    clear_dir_contents "$profile/offlineCache"
    clear_dir_contents "$profile/storage/default"
    clear_dir_contents "$profile/storage/permanent"
    clear_dir_contents "$profile/thumbnails"
    wipe_paths \
      "$profile/cookies.sqlite" \
      "$profile/cookies.sqlite-shm" \
      "$profile/cookies.sqlite-wal" \
      "$profile/webappsstore.sqlite" \
      "$profile/webappsstore.sqlite-shm" \
      "$profile/webappsstore.sqlite-wal" \
      "$profile/sessionstore.jsonlz4" \
      "$profile/sessionstore-backups"
  done
}

clean_browser_scope() {
  local home_dir="$1"
  note "== browser scope =="
  kill_browser_processes
  clean_safari "$home_dir"
  clean_chromium_family "$home_dir/Library/Application Support/Google/Chrome"
  clean_chromium_family "$home_dir/Library/Application Support/Google/Chrome Canary"
  clean_chromium_family "$home_dir/Library/Application Support/Chromium"
  clean_chromium_family "$home_dir/Library/Application Support/BraveSoftware/Brave-Browser"
  clean_chromium_family "$home_dir/Library/Application Support/Microsoft Edge"
  clean_chromium_family "$home_dir/Library/Application Support/Arc/User Data"
  clean_firefox_family "$home_dir/Library/Application Support/Firefox/Profiles"
  clean_firefox_family "$home_dir/Library/Application Support/LibreWolf/Profiles"
}

if (( INCLUDE_SYSTEM )); then
  clean_system_scope
fi

if (( INCLUDE_USER )); then
  clean_user_scope "$TARGET_HOME"
  if (( INCLUDE_BROWSERS )); then
    clean_browser_scope "$TARGET_HOME"
  fi
fi

note "== summary =="
note "planned_actions=$actions"
note "failures=$failures"
note "dry_run=$DRY_RUN"
