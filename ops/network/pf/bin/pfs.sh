#!/usr/bin/env bash
# dev-cmd: alias=pfs name="PF Status" group=net run=sudo desc="Show PF on/off status and recent log output"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT_DIR/bin/pfkit.sh" status "$@"
