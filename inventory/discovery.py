from __future__ import annotations

import os
from collections import defaultdict
from pathlib import Path

from inventory.shared import (
    ALIAS_RE,
    FUNC_RE,
    LEGEND_RE,
    SCHEMA_VERSION,
    SECTION_RE,
    SH_META_RE,
    derive_group,
    is_excluded,
    meta_keywords,
    node_key,
    order_key,
    parse_md_desc,
    parse_md_doc,
    parse_md_meta,
    parse_sh_meta,
    parse_taxonomy_meta,
    rel_str,
    shell_group,
    shell_owner,
    short_taxonomy_key,
    split_keywords,
    split_rel_parts,
    top_component,
)


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
        keywords = meta_keywords(meta, component)
        parent = "" if rel == "." else top_component(rel)
        records.append(
            {
                "type": "dir",
                "source": "readme",
                "path": rel,
                "rel": rel,
                "kind": kind,
                "component": component,
                "owner": component,
                "group": parent or "root",
                "parent": parent,
                "keywords": keywords,
                "tags": keywords,
                "desc": desc,
                "taxonomy": meta.get("taxonomy", ""),
            }
        )
    return records


def build_dir_lookup(dir_records: list[dict[str, str]]) -> tuple[dict[str, dict[str, str]], dict[str, str]]:
    by_rel = {record["rel"]: record for record in dir_records}
    explicit_paths = {
        record["component"]: record["rel"]
        for record in dir_records
        if record["kind"] in {"component", "subcomponent"}
    }
    return by_rel, explicit_paths


def nearest_explicit_component(dir_rel: str, by_rel: dict[str, dict[str, str]]) -> str:
    cur = dir_rel
    while True:
        record = by_rel.get(cur)
        if record and record["kind"] in {"component", "subcomponent"}:
            return record["component"]
        if cur in {"", "."}:
            break
        cur = cur.rsplit("/", 1)[0] if "/" in cur else "."
    return top_component(dir_rel)


def nearest_readme_rel(dir_rel: str, by_rel: dict[str, dict[str, str]]) -> str:
    cur = dir_rel
    while True:
        if cur in by_rel:
            return cur
        if cur in {"", "."}:
            break
        cur = cur.rsplit("/", 1)[0] if "/" in cur else "."
    return "."


def doc_for_rel(dir_rel: str, by_rel: dict[str, dict[str, str]], root: Path) -> str:
    readme_rel = nearest_readme_rel(dir_rel, by_rel)
    readme = root / readme_rel / "README.md" if readme_rel != "." else root / "README.md"
    if readme.is_file():
        return parse_md_doc(readme)
    return ""


def docs_path_for_rel(dir_rel: str, by_rel: dict[str, dict[str, str]]) -> str:
    readme_rel = nearest_readme_rel(dir_rel, by_rel)
    if readme_rel == ".":
        return "README.md"
    if readme_rel:
        return f"{readme_rel}/README.md"
    return ""


def script_group(dir_rel: str, owner: str, by_rel: dict[str, dict[str, str]], explicit_paths: dict[str, str]) -> str:
    nearest_rel = nearest_readme_rel(dir_rel, by_rel)
    owner_rel = explicit_paths.get(owner, owner)
    if nearest_rel == owner_rel:
        rel_from_owner = dir_rel[len(owner_rel):].lstrip("/") if owner_rel != "." else dir_rel
        return rel_from_owner or "scripts"
    if nearest_rel == ".":
        return "scripts"
    if owner_rel != "." and nearest_rel.startswith(owner_rel + "/"):
        trimmed = nearest_rel[len(owner_rel) + 1 :]
        return trimmed or "scripts"
    return nearest_rel


def build_script_records(root: Path, dir_records: list[dict[str, str]]) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    by_rel, explicit_paths = build_dir_lookup(dir_records)
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
        owner = nearest_explicit_component(dir_rel, by_rel)
        records.append(
            {
                "type": "cmd",
                "source": "script",
                "path": rel,
                "rel": rel,
                "component": owner,
                "owner": owner,
                "group": derive_group(owner, meta_keywords(meta, owner), script_group(dir_rel, owner, by_rel, explicit_paths)),
                "name": meta.get("name", meta.get("alias", script.stem)),
                "cmd": meta.get("cmd", meta.get("alias", script.name)),
                "run": meta.get("run", "user"),
                "keywords": meta_keywords(meta, owner),
                "tags": meta_keywords(meta, owner),
                "alias": meta.get("alias", ""),
                "desc": desc,
                "docs": doc_for_rel(dir_rel, by_rel, root),
                "taxonomy": meta.get("taxonomy", ""),
            }
        )
    return records


def parse_shell_commands(shell_file: Path, root: Path, by_rel: dict[str, dict[str, str]]) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    section = "dev"
    component = shell_owner(section)
    pending: dict[str, str] = {}
    rel = rel_str(shell_file, root)
    for raw in shell_file.read_text(errors="ignore").splitlines():
        line = raw.rstrip()
        section_match = SECTION_RE.match(line)
        if section_match:
            section = section_match.group(1).strip().lower()
            component = shell_owner(section)
            pending = {}
            continue
        meta_match = SH_META_RE.match(line)
        if meta_match:
            key = meta_match.group(1)
            value = meta_match.group(2) if meta_match.group(2) is not None else meta_match.group(3) or ""
            if key == "component":
                component = value or shell_owner(section)
                pending = {}
            else:
                pending[key] = value
            continue
        legend_match = LEGEND_RE.match(line)
        if legend_match:
            pending = {
                "name": legend_match.group(1).strip(),
                "cmd": legend_match.group(1).strip(),
                "desc": legend_match.group(2).strip(),
            }
            continue

        matched_name = ""
        alias_match = ALIAS_RE.match(line.strip())
        if alias_match:
            matched_name = alias_match.group(1)
        else:
            func_match = FUNC_RE.match(line.strip())
            if func_match:
                matched_name = func_match.group(1)

        if matched_name:
            expected_cmd = pending.get("cmd", matched_name)
            if matched_name == expected_cmd and pending.get("desc"):
                owner = pending.get("component") or component
                keywords = meta_keywords(pending, f"shell {owner} {shell_group(section)}")
                records.append(
                    {
                        "type": "cmd",
                        "source": "shell",
                        "path": rel,
                        "rel": rel,
                        "component": owner,
                        "owner": owner,
                        "group": derive_group(owner, keywords, shell_group(section)),
                        "name": pending.get("name", matched_name),
                        "cmd": expected_cmd,
                        "run": pending.get("run", "user"),
                        "keywords": keywords,
                        "tags": keywords,
                        "alias": expected_cmd,
                        "desc": pending["desc"],
                        "docs": doc_for_rel(rel_str(shell_file.parent, root), by_rel, root),
                        "taxonomy": pending.get("taxonomy", ""),
                    }
                )
            pending = {}
            continue

        if line.strip() and not line.lstrip().startswith("#"):
            pending = {}
    return records


def build_shell_records(root: Path, by_rel: dict[str, dict[str, str]]) -> list[dict[str, str]]:
    shell_dir = root / "bootstrap" / "shell"
    if not shell_dir.is_dir():
        return []
    records: list[dict[str, str]] = []
    for shell_file in sorted(shell_dir.glob("*.sh")):
        records.extend(parse_shell_commands(shell_file, root, by_rel))
    return records


def display_records(cmd_records: list[dict[str, str]]) -> list[dict[str, str]]:
    selected: list[dict[str, str]] = []
    seen: dict[tuple[str, str, str, str], int] = {}
    for record in sorted(cmd_records, key=lambda x: (order_key(x["component"]), x["group"], x["source"], x["alias"] or x["name"])):
        key = (record["component"], record["group"], record["desc"], record["run"])
        current = seen.get(key)
        if current is None:
            seen[key] = len(selected)
            selected.append(record)
            continue
        incumbent = selected[current]
        if incumbent["source"] != "shell" and record["source"] == "shell":
            selected[current] = record
    return selected


def taxonomy_path(record: dict[str, str], owner_taxonomy: list[str] | None = None) -> list[str]:
    explicit = parse_taxonomy_meta(record.get("taxonomy", ""))
    if explicit:
        return explicit
    if record["type"] == "dir":
        parts = split_rel_parts(record["path"])
        return parts or [record["component"]]
    cmd = record.get("cmd", record.get("alias") or record.get("name") or "")
    if owner_taxonomy:
        return [part for part in owner_taxonomy + [record.get("group", ""), cmd] if part]
    return [part for part in [record.get("component", ""), record.get("group", ""), cmd] if part]


def parent_key_for_dir(record: dict[str, str], by_rel: dict[str, dict[str, str]]) -> str | None:
    rel = record["rel"]
    if rel == ".":
        return None
    cur = rel.rsplit("/", 1)[0] if "/" in rel else "."
    while True:
        parent = by_rel.get(cur)
        if parent:
            return node_key(parent)
        if cur in {"", "."}:
            break
        cur = cur.rsplit("/", 1)[0] if "/" in cur else "."
    return "dir:."


def parent_key_for_cmd(record: dict[str, str], explicit_paths: dict[str, str]) -> str | None:
    owner = record.get("component", "")
    owner_rel = explicit_paths.get(owner)
    if owner_rel:
        return f"dir:{owner_rel}"
    return "dir:." if owner else None


def catalog_item_for_dir(record: dict[str, str], by_rel: dict[str, dict[str, str]]) -> dict[str, object]:
    taxon = taxonomy_path(record)
    declared_taxonomy = record.get("taxonomy", "").strip() or None
    return {
        "key": short_taxonomy_key(taxon),
        "path_key": node_key(record),
        "path": record["path"],
        "docs_path": docs_path_for_rel(record["rel"], by_rel),
        "record_type": "dir",
        "entity_type": record["kind"],
        "source": record["source"],
        "component_id": record["component"],
        "parent_component_id": record.get("parent") or None,
        "parent_key": parent_key_for_dir(record, by_rel),
        "group": None,
        "name": record["component"],
        "cmd": None,
        "run": None,
        "desc": record["desc"],
        "keywords": split_keywords(record.get("keywords", "")),
        "alias": None,
        "declared_taxonomy": declared_taxonomy,
        "taxonomy_source": "explicit" if declared_taxonomy else "derived",
        "taxonomy_key": "/".join(taxon),
        "taxonomy_path": taxon,
    }


def catalog_item_for_cmd(
    record: dict[str, str], by_rel: dict[str, dict[str, str]], explicit_paths: dict[str, str]
) -> dict[str, object]:
    cmd = record.get("cmd", record.get("alias") or record.get("name") or "")
    owner_rel = explicit_paths.get(record.get("component", ""), ".")
    owner_record = by_rel.get(owner_rel)
    owner_taxonomy = taxonomy_path(owner_record) if owner_record else None
    taxon = taxonomy_path(record, owner_taxonomy=owner_taxonomy)
    declared_taxonomy = record.get("taxonomy", "").strip() or None
    return {
        "key": short_taxonomy_key(taxon),
        "path_key": node_key(record),
        "path": record["path"],
        "docs_path": docs_path_for_rel(owner_rel, by_rel),
        "record_type": "cmd",
        "entity_type": "command",
        "source": record["source"],
        "component_id": record["component"],
        "parent_component_id": record["component"],
        "parent_key": parent_key_for_cmd(record, explicit_paths),
        "group": record.get("group") or None,
        "name": record.get("name") or cmd,
        "cmd": cmd,
        "run": record.get("run", "user"),
        "desc": record["desc"],
        "keywords": split_keywords(record.get("keywords", "")),
        "alias": record.get("alias") or None,
        "declared_taxonomy": declared_taxonomy,
        "taxonomy_source": "explicit" if declared_taxonomy else "derived",
        "taxonomy_key": "/".join(taxon),
        "taxonomy_path": taxon,
    }


def collect_manifest_index(
    root: Path,
    dir_records: list[dict[str, str]],
    script_records: list[dict[str, str]],
    shell_records: list[dict[str, str]],
    emitted_cmd_records: list[dict[str, str]],
    emitted_items_count: int,
) -> dict[str, object]:
    eligible_dirs: list[str] = []
    skipped_dirs: list[str] = []
    skipped_counts: defaultdict[str, int] = defaultdict(int)

    readmes_seen = 0
    scripts_seen = 0
    scripts_eligible = 0
    shell_files_seen = 0

    for current_root, dirnames, filenames in os.walk(root):
        current_path = Path(current_root)
        eligible_dirs.append(rel_str(current_path, root))

        kept_dirs: list[str] = []
        for dirname in dirnames:
            child = current_path / dirname
            if is_excluded(child, root):
                skipped_dirs.append(rel_str(child, root))
                skipped_counts["excluded_dirs"] += 1
            else:
                kept_dirs.append(dirname)
        dirnames[:] = kept_dirs

        for filename in filenames:
            path = current_path / filename
            if filename == "README.md":
                readmes_seen += 1

            if path.suffix not in {".sh", ".zsh"}:
                continue

            scripts_seen += 1

            if rel_str(path, root).startswith("bootstrap/shell/"):
                shell_files_seen += 1

            if not os.access(path, os.X_OK):
                skipped_counts["non_executable_scripts"] += 1
                continue

            meta = parse_sh_meta(path)
            if not meta.get("desc", ""):
                skipped_counts["scripts_missing_desc"] += 1
                continue

            scripts_eligible += 1

    component_count = sum(1 for record in dir_records if record["kind"] == "component")
    subcomponent_count = sum(1 for record in dir_records if record["kind"] == "subcomponent")
    support_count = sum(1 for record in dir_records if record["kind"] == "support")

    return {
        "name": "manifest_index",
        "root_key": "dir:.",
        "eligible_dirs": sorted(eligible_dirs),
        "skipped_dirs": sorted(skipped_dirs),
        "counts": {
            "eligible_dirs": len(eligible_dirs),
            "skipped_dirs": len(skipped_dirs),
            "readmes_seen": readmes_seen,
            "dir_records": len(dir_records),
            "components": component_count,
            "subcomponents": subcomponent_count,
            "support_dirs": support_count,
            "scripts_seen": scripts_seen,
            "scripts_eligible": scripts_eligible,
            "script_records": len(script_records),
            "shell_files_seen": shell_files_seen,
            "shell_records": len(shell_records),
            "command_records_manifest": len(emitted_cmd_records),
            "items_emitted": emitted_items_count,
        },
        "skipped": dict(sorted(skipped_counts.items())),
    }


def collect_records(root: Path) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, str]], list[dict[str, str]]]:
    dir_records = build_dir_records(root)
    script_records = build_script_records(root, dir_records)
    shell_records = build_shell_records(root, {record["rel"]: record for record in dir_records})
    cmd_records = script_records + shell_records
    return dir_records, script_records, shell_records, cmd_records
