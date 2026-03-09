#!/usr/bin/env bash
# @desc: Merge local Zeek log files into the canonical configured log dir
# @tags: audit zeek logs sync
# @run: user

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:-$ROOT_DIR}"
TARGET_DIR="${2:-${ZEEK_LOG_DIR:-$ROOT_DIR/../zlogs}}"
FILES=(conn.log dns.log http.log ssl.log quic.log files.log weird.log packet_filter.log)

usage() {
  cat <<EOF
Usage:
  ./zeek-logsync.sh [source_dir] [target_dir]

Defaults:
  source_dir = $ROOT_DIR
  target_dir = ${ZEEK_LOG_DIR:-$ROOT_DIR/../zlogs}

Behavior:
  - copies missing Zeek log files into the target dir
  - appends source data rows onto existing target logs
  - keeps the source files in place
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$TARGET_DIR"

header_without_close() {
  awk '
    /^#/ {
      if ($1 == "#close")
        next
      print
      next
    }
    { exit }
  ' "$1"
}

data_only() {
  awk '!/^#/' "$1"
}

close_line() {
  awk '/^#close/ { last=$0 } END { if (last != "") print last }' "$1"
}

meta_value() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '$1 == key { print $2; exit }' "$file"
}

merge_one() {
  local src="$1"
  local dst="$2"
  local tmp
  tmp="$(mktemp "$TARGET_DIR/.zeek-merge.XXXXXX")"

  local src_path dst_path src_fields dst_fields
  src_path="$(meta_value "#path" "$src")"
  dst_path="$(meta_value "#path" "$dst")"
  src_fields="$(meta_value "#fields" "$src")"
  dst_fields="$(meta_value "#fields" "$dst")"

  if [[ -n "$src_path" && -n "$dst_path" && "$src_path" != "$dst_path" ]]; then
    echo "skip: path mismatch for $(basename "$src") ($src_path vs $dst_path)" >&2
    rm -f "$tmp"
    return
  fi

  if [[ -n "$src_fields" && -n "$dst_fields" && "$src_fields" != "$dst_fields" ]]; then
    echo "skip: field mismatch for $(basename "$src")" >&2
    rm -f "$tmp"
    return
  fi

  {
    header_without_close "$dst"
    data_only "$dst"
    data_only "$src"
    close_line "$src" || close_line "$dst"
  } > "$tmp"

  mv "$tmp" "$dst"
  echo "merged $(basename "$src") -> $dst"
}

for name in "${FILES[@]}"; do
  src="$SOURCE_DIR/$name"
  dst="$TARGET_DIR/$name"
  [[ -f "$src" ]] || continue

  if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    echo "copied $src -> $dst"
    continue
  fi

  if cmp -s "$src" "$dst"; then
    echo "unchanged $dst"
    continue
  fi

  merge_one "$src" "$dst"
done
