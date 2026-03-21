#!/usr/bin/env python3
# dev-cmd: alias=component-scan name="Component Scan" group=sys run=user legend=hide desc="Scan the dev tree and emit canonical component inventory and validation output"

from __future__ import annotations

import sys

from inventory.cli import main


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
