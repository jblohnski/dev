#!/usr/bin/env bash
# dev-cmd: alias=pfo name="PF On" group=net run=sudo desc="Start / apply pfkit rules and start logging"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT_DIR/bin/pfkit.sh" on "$@"
