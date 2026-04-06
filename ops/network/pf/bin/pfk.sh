#!/usr/bin/env bash
# dev-cmd: alias=pfk name="PF Kill" group=net run=sudo desc="Stop / kill pfkit rules and stop logging"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT_DIR/bin/pfkit.sh" off "$@"
