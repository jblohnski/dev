#!/usr/bin/env bash
# dev-cmd: alias=pfst name=pfkit-status group=net run=sudo desc="Check PFKit"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT_DIR/bin/pfkit.sh" status "$@"
