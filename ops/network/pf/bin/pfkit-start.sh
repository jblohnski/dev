#!/usr/bin/env bash
# dev-cmd: alias=pfkit-start name=pfkit-start group=net run=sudo desc="Enable PF, update PFKit rules, and start logging"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT_DIR/bin/pfkit.sh" start "$@"
