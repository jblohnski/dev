#!/usr/bin/env bash
# dev-cmd: alias=pflg name=pfkit-logs group=net run=sudo desc="manage pfkit logs"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT_DIR/pfkit.sh" logs "$@"
