#!/usr/bin/env bash
# dev-cmd: alias=pfkit.stop name="PFKit Stop (pfkit.stop)" group=net run=sudo desc="Disable PF globally, stop logging, and unload PFKit rules"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT_DIR/bin/pfkit.sh" stop "$@"
