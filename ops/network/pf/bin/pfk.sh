#!/usr/bin/env bash
# dev-cmd: alias=pfk name="PF Kill" group=net run=sudo desc="Disable PF globally, stop pfkit logging, and unload the pfkit anchor"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT_DIR/bin/pfkit.sh" off "$@"
