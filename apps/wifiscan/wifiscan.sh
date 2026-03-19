#!/usr/bin/env bash
# @name: Native Wi-Fi scan
# @desc: Scan nearby Wi-Fi networks via CoreWLAN with macOS permission diagnostics
# @cmd: wifiscan
# @keywords: wifi network scan macos native
# @run: user
# @alias: wifiscan

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_PATH="${SCRIPT_DIR}/wifiscan-bin"
SOURCE_PATH="${SCRIPT_DIR}/main.swift"

if [[ -x "${BIN_PATH}" ]]; then
  exec "${BIN_PATH}" "$@"
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift toolchain not found" >&2
  echo "build ${BIN_PATH} with swiftc, or install Xcode Command Line Tools" >&2
  exit 1
fi

exec /usr/bin/env swift "${SOURCE_PATH}" "$@"
