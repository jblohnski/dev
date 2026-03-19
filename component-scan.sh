#!/usr/bin/env python3
# @desc: Scan the dev tree and emit canonical component inventory and validation output
# @tags: dev component inventory metadata
# @run: user

from __future__ import annotations

import sys

from inventory.cli import main


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
