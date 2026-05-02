#!/usr/bin/env bash
# dev-cmd: alias=pfup name=pfkit-update group=net run=sudo desc="update pfkit"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT_DIR/pfkit.sh" update "$@"
