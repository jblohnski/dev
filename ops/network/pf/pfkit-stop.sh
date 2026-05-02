#!/usr/bin/env bash
# dev-cmd: alias=pfof name=pfkit-stop group=net run=sudo desc="stop pfkit"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT_DIR/pfkit.sh" stop "$@"
