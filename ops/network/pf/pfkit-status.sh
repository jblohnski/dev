#!/usr/bin/env bash
# dev-cmd: alias=pfst name=pfkit-status group=net run=sudo desc="check pfkit"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT_DIR/pfkit.sh" status "$@"
