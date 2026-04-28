#!/usr/bin/env bash
# dev-cmd: alias=pfon name=pfkit-start group=net run=sudo desc="Start PFKit"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT_DIR/bin/pfkit.sh" start "$@"
