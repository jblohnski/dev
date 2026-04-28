#!/usr/bin/env bash
# dev-cmd: alias=wfs name=wifiscan group=net run=user desc="Scan Wi-Fi"

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
