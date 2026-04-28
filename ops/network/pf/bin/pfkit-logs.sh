#!/usr/bin/env bash
# dev-cmd: alias=pfkit-logs name=pfkit-logs group=net run=sudo desc="Report, tail, print, or clear retained PFKit block logs"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT_DIR/bin/pfkit.sh" logs "$@"
