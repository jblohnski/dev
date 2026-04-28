#!/usr/bin/env bash
# dev-cmd: alias=pfkit-status name=pfkit-status group=net run=sudo desc="Show whether PFKit, PF rules, logger, and pflog0 are running"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT_DIR/bin/pfkit.sh" status "$@"
