#!/usr/bin/env bash
# dev-cmd: alias=pfup name=pfkit-update group=net run=sudo desc="Update PFKit"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT_DIR/bin/pfkit.sh" update "$@"
