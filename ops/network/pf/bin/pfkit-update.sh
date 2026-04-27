#!/usr/bin/env bash
# dev-cmd: alias=pfkit.update name="PFKit Update (pfkit.update)" group=net run=sudo desc="Repair PFKit files and wiring, render config, and load PF rules"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT_DIR/bin/pfkit.sh" update "$@"
