#!/usr/bin/env python3
# @desc: Walk the dev tree and emit component and command inventory records
# @tags: dev component dashboard metadata
# @run: user

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


MD_META_RE = re.compile(r"^<!-- @\s*([a-z]+):\s*(.*?)\s*-->$")
SH_META_RE = re.compile(r"^# @\s*([a-z]+):\s*(.*?)\s*$")
EXCLUDED_PARTS = {".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build", "target"}


def parse_args(argv: list[str]) -> tuple[Path, str]:
    root = Path.home() / "dev"
    mode = "summary"
    if len(argv) >= 2:
      if argv[1] in {"summary", "records"}:
          mode = argv[1]
      else:
          root = Path(argv[1]).expanduser()
    if len(argv) >= 3:
        mode = argv[2]
    return root, mode


def is_excluded(path: Path, root: Path) -> bool:
    try:
        rel = path.relative_to(root)
    except ValueError:
        return True
    return any(part in EXCLUDED_PARTS for part in rel.parts)


def rel_str(path: Path, root: Path) -> str:
    rel = path.relative_to(root)
    return "." if str(rel) == "." else str(rel)


def top_component(rel: str) -> str:
    if rel == ".":
        return "dev"
    return rel.split("/", 1)[0]


def parse_md_meta(readme: Path) -> dict[str, str]:
    meta: dict[str, str] = {}
    for line in readme.read_text(errors="ignore").splitlines():
        match = MD_META_RE.match(line.strip())
        if match:
            meta[match.group(1)] = match.group(2)
        elif line.strip() and not line.startswith("<!--"):
            break
    return meta


def parse_md_desc(readme: Path) -> str:
    for line in readme.read_text(errors="ignore").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("<!--") or stripped.startswith("#"):
            continue
        return stripped
    return ""


def parse_sh_meta(script: Path) -> dict[str, str]:
    meta: dict[str, str] = {}
    for line in script.read_text(errors="ignore").splitlines():
        match = SH_META_RE.match(line.rstrip())
        if match:
            meta[match.group(1)] = match.group(2)
        elif meta and line and not line.startswith("#"):
            break
    return meta


def build_dir_records(root: Path) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    for readme in sorted(root.rglob("README.md")):
        if is_excluded(readme, root):
            continue
        directory = readme.parent
        rel = rel_str(directory, root)
        meta = parse_md_meta(readme)
        kind = meta.get("kind", "support")
        component = meta.get("component", directory.name if rel != "." else "dev")
        desc = meta.get("desc", parse_md_desc(readme))
        tags = meta.get("tags", component)
        parent = "" if rel == "." else top_component(rel)
        records.append(
            {
                "type": "dir",
                "rel": rel,
                "kind": kind,
                "component": component,
                "parent": parent,
                "tags": tags,
                "desc": desc,
            }
        )
    return records


def nearest_component(dir_rel: str, dir_records: list[dict[str, str]]) -> str:
    explicit = {
        record["rel"]: record["component"]
        for record in dir_records
        if record["kind"] in {"component", "subcomponent"}
    }
    cur = dir_rel
    while True:
        if cur in explicit:
            return explicit[cur]
        if cur in {"", "."}:
            break
        cur = cur.rsplit("/", 1)[0] if "/" in cur else "."
    return top_component(dir_rel)


def build_cmd_records(root: Path, dir_records: list[dict[str, str]]) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    for script in sorted(root.rglob("*")):
        if not script.is_file() or script.suffix not in {".sh", ".zsh"}:
            continue
        if is_excluded(script, root) or not os.access(script, os.X_OK):
            continue
        meta = parse_sh_meta(script)
        desc = meta.get("desc", "")
        if not desc:
            continue
        rel = rel_str(script, root)
        dir_rel = rel_str(script.parent, root)
        records.append(
            {
                "type": "cmd",
                "rel": rel,
                "component": nearest_component(dir_rel, dir_records),
                "group": dir_rel,
                "name": script.name,
                "run": meta.get("run", "user"),
                "tags": meta.get("tags", top_component(dir_rel)),
                "alias": meta.get("alias", ""),
                "desc": desc,
            }
        )
    return records


def print_records(dir_records: list[dict[str, str]], cmd_records: list[dict[str, str]]) -> None:
    for record in dir_records:
        print(
            "\t".join(
                [
                    "dir",
                    record["rel"],
                    record["kind"],
                    record["component"],
                    record["parent"],
                    record["tags"],
                    record["desc"],
                ]
            )
        )
    for record in cmd_records:
        alias = record["alias"] or "-"
        print(
            "\t".join(
                [
                    "cmd",
                    record["rel"],
                    record["component"],
                    record["group"],
                    record["name"],
                    record["run"],
                    record["tags"],
                    alias,
                    record["desc"],
                ]
            )
        )


def print_summary(dir_records: list[dict[str, str]], cmd_records: list[dict[str, str]]) -> None:
    components = [record for record in dir_records if record["kind"] == "component" or record["rel"] == "."]
    subcomponents = [record for record in dir_records if record["kind"] == "subcomponent"]
    for component in components:
        print(f'{component["component"]} [{component["kind"]}] {component["desc"]}')
        for sub in subcomponents:
            if top_component(sub["rel"]) == component["component"]:
                print(f'  + {sub["component"]} [{sub["kind"]}] {sub["desc"]}')
        for cmd in cmd_records:
            if cmd["component"] == component["component"]:
                display_name = cmd["alias"] or cmd["name"]
                print(f'  - {display_name} ({cmd["run"]}) {cmd["desc"]}')
        print()


def main(argv: list[str]) -> int:
    root, mode = parse_args(argv)
    if not root.is_dir():
        print(f"error: root not found: {root}", file=sys.stderr)
        return 1
    if mode not in {"summary", "records"}:
        print(f"usage: {argv[0]} [root] [summary|records]", file=sys.stderr)
        return 2

    dir_records = build_dir_records(root)
    cmd_records = build_cmd_records(root, dir_records)
    if mode == "records":
        print_records(dir_records, cmd_records)
    else:
        print_summary(dir_records, cmd_records)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
