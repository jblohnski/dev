from __future__ import annotations

import sys

from inventory.discovery import collect_records
from inventory.output import print_index, print_legend, print_manifest, print_records, print_summary
from inventory.shared import MODE_SET, parse_args
from inventory.validate import validate


def main(argv: list[str]) -> int:
    root, mode, show_paths, color, filters = parse_args(argv)
    if not root.is_dir():
        print(f"error: root not found: {root}", file=sys.stderr)
        return 1
    if mode not in MODE_SET:
        print(
            f"usage: {argv[0]} [root] [summary|records|legend|validate|index|catalog|manifest] [--paths] [filters...]",
            file=sys.stderr,
        )
        return 2

    dir_records, script_records, shell_records, cmd_records = collect_records(root)

    if mode == "records":
        print_records(dir_records, cmd_records)
        return 0
    if mode == "summary":
        print_summary(dir_records, cmd_records, show_paths, color, filters)
        return 0
    if mode == "legend":
        print_legend(cmd_records, show_paths, color, filters)
        return 0
    if mode == "index":
        print_index(cmd_records, filters)
        return 0
    if mode in {"catalog", "manifest"}:
        print_manifest(root, dir_records, script_records, shell_records, cmd_records, filters)
        return 0
    return validate(root, dir_records, script_records, shell_records)
