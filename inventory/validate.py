from __future__ import annotations

import os
from pathlib import Path

from inventory.operations import valid_operations
from inventory.shared import SECTION_RE, SHELL_SECTION_OWNER, VALID_KINDS, VALID_RUN, is_excluded, parse_md_meta, parse_sh_meta, rel_str


def validate(root: Path, dir_records: list[dict[str, str]], script_records: list[dict[str, str]], shell_records: list[dict[str, str]]) -> int:
    warnings: list[str] = []
    errors: list[str] = []

    component_ids: dict[str, str] = {}
    for record in dir_records:
        readme = root / record["path"] / "README.md" if record["path"] != "." else root / "README.md"
        meta = parse_md_meta(readme)
        if record["kind"] not in VALID_KINDS:
            errors.append(f"{record['path']}: invalid @kind '{record['kind']}'")
        if not meta:
            warnings.append(f"{record['path']}: implicit support README without explicit component metadata")
        comp = record["component"]
        if comp in component_ids and component_ids[comp] != record["path"]:
            errors.append(f"duplicate component id '{comp}' in {record['path']} and {component_ids[comp]}")
        component_ids[comp] = record["path"]

    for script in sorted(root.rglob("*")):
        if not script.is_file() or script.suffix not in {".sh", ".zsh"}:
            continue
        if is_excluded(script, root) or not os.access(script, os.X_OK):
            continue
        meta = parse_sh_meta(script)
        rel = rel_str(script, root)
        if rel.startswith("arkenfox/") or rel.startswith("projects/"):
            continue
        if rel.startswith("bootstrap/shell/"):
            continue
        for key in ("desc", "run"):
            if key not in meta:
                warnings.append(f"{rel}: missing script metadata @{key}")
        if "keywords" not in meta and "tags" not in meta:
            warnings.append(f"{rel}: missing script metadata @keywords")
        if "run" in meta and meta["run"] not in VALID_RUN:
            errors.append(f"{rel}: invalid @run '{meta['run']}'")

    shell_dir = root / "bootstrap" / "shell"
    if shell_dir.is_dir():
        for shell_file in sorted(shell_dir.glob("*.sh")):
            section = ""
            for line in shell_file.read_text(errors="ignore").splitlines():
                match = SECTION_RE.match(line.rstrip())
                if match:
                    section = match.group(1).strip().lower()
                    if section not in SHELL_SECTION_OWNER:
                        warnings.append(f"{rel_str(shell_file, root)}: non-canonical shell section '{section}'")

    if not shell_records:
        warnings.append("bootstrap/shell: no shell command records discovered")

    op_candidates = []
    for record in script_records + shell_records:
        op_candidates.append(
            {
                "key": record.get("cmd", record.get("alias") or record.get("name") or ""),
                "path_key": f'{record.get("source", "cmd")}:{record.get("path", "")}#{record.get("cmd", record.get("alias") or record.get("name") or "")}',
                "component_id": record.get("component", ""),
                "name": record.get("name", ""),
                "cmd": record.get("cmd", ""),
                "path": record.get("path", ""),
                "group": record.get("group"),
                "run": record.get("run"),
                "keywords": [part for part in (record.get("keywords", "") or "").split() if part],
                "alias": record.get("alias") or None,
                "source": record.get("source"),
                "taxonomy_key": "/".join(part for part in [record.get("component", ""), record.get("group", ""), record.get("cmd", "")] if part),
                "taxonomy_path": [part for part in [record.get("component", ""), record.get("group", ""), record.get("cmd", "")] if part],
                "desc": record.get("desc", ""),
            }
        )

    valid_path_keys = {op["path_key"] for op in valid_operations(op_candidates)}
    for candidate in op_candidates:
        if candidate["path_key"] not in valid_path_keys:
            errors.append(f"{candidate['path']}: discovered command record did not produce a valid operation object")

    for message in errors:
        print(f"ERROR {message}")
    for message in warnings:
        print(f"WARN  {message}")
    if not errors and not warnings:
        print("OK component metadata validated")
    return 1 if errors else 0
