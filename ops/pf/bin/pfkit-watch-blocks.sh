#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../network/pf" && pwd)"
exec "$ROOT_DIR/bin/pfkit-watch-blocks.sh" "$@"
