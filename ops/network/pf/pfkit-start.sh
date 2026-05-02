#!/usr/bin/env bash
# dev-cmd: alias=pfon name=pfkit-start group=net run=sudo desc="start pfkit"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT_DIR/pfkit.sh" start "$@"
