from __future__ import annotations

import os
from pathlib import Path

from command_contract import is_valid
from inventory.commands import command_object
from inventory.discovery import is_legend_eligible
from inventory.shared import SECTION_RE, SHELL_SECTION_OWNER, VALID_GROUPS, VALID_KINDS, VALID_RUN, is_excluded, parse_md_meta, parse_sh_meta, rel_str


INTERNAL_SCRIPT_PREFIXES = (
    "ops/network/pf/bin/pfkit",
)

ROOT_SCRIPT_ALLOWLIST = {
    "component-scan.sh",
    "devdash",
}

SCRIPT_LIKE_SUFFIXES = {".sh", ".zsh"}


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
        else:
            for key in ("component", "kind", "group", "desc"):
                if key not in meta:
                    warnings.append(f"{record['path']}/README.md: missing directory metadata @{key}")
            if "group" in meta and meta["group"] not in VALID_GROUPS:
                errors.append(f"{record['path']}/README.md: invalid group '{meta['group']}'")
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
        if any(rel.startswith(prefix) for prefix in INTERNAL_SCRIPT_PREFIXES):
            continue
        for key in ("alias", "name", "group", "desc"):
            if key not in meta:
                warnings.append(f"{rel}: missing script metadata @{key}")
        if "run" in meta and meta["run"] not in VALID_RUN:
            errors.append(f"{rel}: invalid @run '{meta['run']}'")
        if "group" in meta and meta["group"] not in VALID_GROUPS:
            errors.append(f"{rel}: invalid group '{meta['group']}'")

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

    command_candidates = []
    alias_paths: dict[str, str] = {}
    for record in script_records + shell_records:
        alias = (record.get("alias") or "").strip()
        name = (record.get("name") or "").strip()
        group = (record.get("group") or "").strip()
        desc = (record.get("desc") or "").strip()
        if not alias:
            errors.append(f"{record['path']}: discovered command record missing alias")
        if not name:
            errors.append(f"{record['path']}: discovered command record missing name")
        if not group:
            errors.append(f"{record['path']}: discovered command record missing group")
        elif group not in VALID_GROUPS:
            errors.append(f"{record['path']}: discovered command record has invalid group '{group}'")
        if not desc:
            errors.append(f"{record['path']}: discovered command record missing desc")
        if is_legend_eligible(record) and alias and name and alias not in name:
            errors.append(f"{record['path']}: public command name must contain alias '{alias}'")
        existing_path = alias_paths.get(alias)
        if alias and existing_path and existing_path != record["path"]:
            errors.append(f"duplicate command alias '{alias}' in {record['path']} and {existing_path}")
        elif alias:
            alias_paths[alias] = record["path"]
        command_candidates.append(record)

    for candidate in command_candidates:
        if not is_valid(command_object(candidate)):
            errors.append(f"{candidate['path']}: discovered command record did not produce a valid command object")

    for entry in sorted(root.iterdir()):
        if not entry.is_file() or entry.name.startswith("."):
            continue
        rel = rel_str(entry, root)
        is_script_like = entry.suffix in SCRIPT_LIKE_SUFFIXES or (os.access(entry, os.X_OK) and not entry.suffix)
        if not is_script_like or rel in ROOT_SCRIPT_ALLOWLIST:
            continue
        warnings.append(
            f"{rel}: top-level script-like file is outside the canonical public/internal roots; "
            "move it under an owning component or remove it"
        )

    for message in errors:
        print(f"ERROR {message}")
    for message in warnings:
        print(f"WARN  {message}")
    if not errors and not warnings:
        print("OK component metadata validated")
    return 1 if errors else 0
