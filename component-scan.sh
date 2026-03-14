#!/usr/bin/env python3
# @desc: Scan the dev tree and emit canonical component inventory and validation output
# @tags: dev component inventory metadata
# @run: user

from __future__ import annotations

import os
import re
import sys
from collections import defaultdict
from pathlib import Path


MD_META_RE = re.compile(r"^<!-- @\s*([a-z]+):\s*(.*?)\s*-->$")
SH_META_RE = re.compile(r"^#\s*@([a-z]+)(?::\s*(.*?)\s*|\s+(.+?)\s*)?$")
SECTION_RE = re.compile(r"^##\s+(.+?)\s*$")
LEGEND_RE = re.compile(r"^#\s*([A-Za-z0-9_.-]+):\s+(.+?)\s*$")
ALIAS_RE = re.compile(r"^alias\s+([A-Za-z0-9_.-]+)=")
FUNC_RE = re.compile(r"^([A-Za-z0-9_]+)\s*\(\)\s*\{")

EXCLUDED_PARTS = {".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build", "target"}
VALID_KINDS = {"component", "subcomponent", "support"}
VALID_RUN = {"user", "sudo"}
DEFAULT_ROOT = Path.home() / "dev"
MODE_SET = {"summary", "records", "legend", "validate"}
SHELL_SECTION_OWNER = {
    "bootstrap": "bootstrap",
    "audit": "audit",
    "dev": "dev",
    "python": "dev",
    "nav": "dev",
    "git": "dev",
    "network": "dev",
    "dns": "dev",
    "util": "dev",
}
COMPONENT_ORDER = ["bootstrap", "audit", "ops", "dev", "projects", "proposals", "zlogs", "arkenfox"]
RESERVED_GROUP_KEYWORDS = {
    "automation",
    "command",
    "commands",
    "component",
    "components",
    "inventory",
    "metadata",
    "script",
    "scripts",
    "shell",
    "support",
    "tool",
    "tools",
    "user",
    "sudo",
    "workspace",
}
KEYWORD_ALIASES = {"diag": "diagnostics", "sec": "security"}


class Style:
    def __init__(self, enabled: bool) -> None:
        self.enabled = enabled
        self.reset = "\033[0m" if enabled else ""
        self.bold = "\033[1m" if enabled else ""
        self.hdr = "\033[38;5;110m" if enabled else ""
        self.name = "\033[38;5;153m" if enabled else ""
        self.desc = "\033[38;5;244m" if enabled else ""
        self.accent = "\033[38;5;109m" if enabled else ""

    def wrap(self, text: str, *codes: str) -> str:
        prefix = "".join(code for code in codes if code)
        if not self.enabled or not prefix:
            return text
        return f"{prefix}{text}{self.reset}"


def parse_args(argv: list[str]) -> tuple[Path, str, bool, bool]:
    root = DEFAULT_ROOT
    mode = "summary"
    show_paths = False
    color = sys.stdout.isatty()

    args = argv[1:]
    clean_args: list[str] = []
    for arg in args:
        if arg in {"--paths", "paths"}:
            show_paths = True
        elif arg in {"--color", "color"}:
            color = True
        elif arg in {"--no-color", "no-color"}:
            color = False
        else:
            clean_args.append(arg)

    if clean_args:
        if clean_args[0] in MODE_SET:
            mode = clean_args[0]
        else:
            root = Path(clean_args[0]).expanduser()
    if len(clean_args) >= 2:
        mode = clean_args[1]
    return root, mode, show_paths, color


def is_excluded(path: Path, root: Path) -> bool:
    try:
        rel = path.relative_to(root)
    except ValueError:
        return True
    return any(part in EXCLUDED_PARTS for part in rel.parts)


def rel_str(path: Path, root: Path) -> str:
    rel = path.relative_to(root)
    return "." if str(rel) == "." else str(rel)


def parse_md_meta(readme: Path) -> dict[str, str]:
    meta: dict[str, str] = {}
    for line in readme.read_text(errors="ignore").splitlines():
        match = MD_META_RE.match(line.strip())
        if match:
            meta[match.group(1)] = match.group(2)
        elif line.strip() and not line.lstrip().startswith("<!--"):
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
            value = match.group(2) if match.group(2) is not None else match.group(3)
            meta[match.group(1)] = value or ""
        elif meta and line.strip() and not line.startswith("#"):
            break
    return meta


def meta_keywords(meta: dict[str, str], fallback: str = "") -> str:
    return meta.get("keywords") or meta.get("tags") or fallback


def split_keywords(raw: str) -> list[str]:
    return [KEYWORD_ALIASES.get(part.strip().lower(), part.strip().lower()) for part in raw.split() if part.strip()]


def derive_group(component: str, keywords: str, fallback: str) -> str:
    component_parts = {part for part in re.split(r"[-_/]", component.lower()) if part}
    for keyword in split_keywords(keywords):
        if keyword not in RESERVED_GROUP_KEYWORDS and keyword not in component_parts:
            return keyword
    return fallback


def shell_owner(section: str) -> str:
    return SHELL_SECTION_OWNER.get(section, "dev")


def shell_group(section: str) -> str:
    return "shell" if section in {"bootstrap", "audit", "dev"} else section


def top_component(rel: str) -> str:
    if rel == ".":
        return "dev"
    return rel.split("/", 1)[0]


def order_key(component: str) -> tuple[int, str]:
    try:
        return (COMPONENT_ORDER.index(component), component)
    except ValueError:
        return (999, component)


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


def build_script_records(
    root: Path, dir_records: list[dict[str, str]]
) -> list[dict[str, str]]:
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
            }
        )
    return records


def parse_shell_commands(shell_file: Path, root: Path) -> list[dict[str, str]]:
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
                    }
                )
            pending = {}
            continue

        if line.strip() and not line.lstrip().startswith("#"):
            pending = {}
    return records


def build_shell_records(root: Path) -> list[dict[str, str]]:
    shell_dir = root / "bootstrap" / "shell"
    if not shell_dir.is_dir():
        return []
    records: list[dict[str, str]] = []
    for shell_file in sorted(shell_dir.glob("*.sh")):
        records.extend(parse_shell_commands(shell_file, root))
    return records


def print_records(dir_records: list[dict[str, str]], cmd_records: list[dict[str, str]]) -> None:
    for record in dir_records:
        print(
            "\t".join(
                [
                    "dir",
                    record["source"],
                    record["path"],
                    record["component"],
                    record["kind"],
                    record["parent"],
                    "-",
                    "-",
                    record["keywords"],
                    record["desc"],
                ]
            )
        )
    for record in sorted(cmd_records, key=lambda x: (order_key(x["component"]), x["group"], x["source"], x["alias"] or x["name"])):
        cmd = record.get("cmd", record["alias"] or record["name"])
        print(
            "\t".join(
                [
                    "cmd",
                    record["source"],
                    record["path"],
                    record["component"],
                    record["group"],
                    record["name"],
                    cmd,
                    record["run"],
                    record["keywords"],
                    record["desc"],
                ]
            )
        )


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


def render_command_group(commands: list[dict[str, str]], show_paths: bool, style: Style) -> None:
    for record in commands:
        cmd = record.get("cmd", record["alias"] or record["name"])
        desc = record["desc"]
        cmd_text = style.wrap(cmd, style.accent)
        print(f"    {cmd_text}  {style.wrap(desc, style.desc)}")
        if show_paths:
            print(f"      {style.wrap('@ ' + record['path'], style.desc)}")


def print_summary(dir_records: list[dict[str, str]], cmd_records: list[dict[str, str]], show_paths: bool, color: bool) -> None:
    style = Style(color)
    components = [record for record in dir_records if record["kind"] == "component" and record["rel"] != "."]
    if any(record["rel"] == "." for record in dir_records):
        root_record = next(record for record in dir_records if record["rel"] == ".")
        components = [root_record] + sorted(components, key=lambda x: order_key(x["component"]))
    else:
        components = sorted(components, key=lambda x: order_key(x["component"]))
    subcomponents = [record for record in dir_records if record["kind"] == "subcomponent"]

    cmds_by_component: dict[str, list[dict[str, str]]] = defaultdict(list)
    for record in display_records(cmd_records):
        cmds_by_component[record["component"]].append(record)

    for component in components:
        print(
            f'{style.wrap(component["component"], style.bold, style.hdr)} '
            f'{style.wrap("[" + component["kind"] + "]", style.desc)} '
            f'{style.wrap(component["desc"], style.desc)}'
        )
        for sub in sorted(subcomponents, key=lambda x: x["component"]):
            if sub["parent"] == component["component"]:
                print(
                    f'  + {style.wrap(sub["component"], style.name)} '
                    f'{style.wrap("[" + sub["kind"] + "]", style.desc)} '
                    f'{style.wrap(sub["desc"], style.desc)}'
                )
        grouped: dict[str, list[dict[str, str]]] = defaultdict(list)
        for record in cmds_by_component.get(component["component"], []):
            grouped[record["group"]].append(record)
        for group in sorted(grouped):
            print(f"  > {style.wrap(group, style.accent)}")
            render_command_group(grouped[group], show_paths, style)
        print()


def print_legend(cmd_records: list[dict[str, str]], show_paths: bool, color: bool) -> None:
    style = Style(color)
    print(style.wrap("commands", style.hdr))
    print()
    grouped_by_component: dict[str, list[dict[str, str]]] = defaultdict(list)
    for record in display_records(cmd_records):
        grouped_by_component[record["component"]].append(record)

    for component in sorted(grouped_by_component, key=order_key):
        print(style.wrap(component, style.bold, style.hdr))
        grouped: dict[str, list[dict[str, str]]] = defaultdict(list)
        for record in grouped_by_component[component]:
            grouped[record["group"]].append(record)
        for group in sorted(grouped):
            print(f"  {style.wrap(group, style.accent)}")
            render_command_group(grouped[group], show_paths, style)
        print()


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

    for message in errors:
        print(f"ERROR {message}")
    for message in warnings:
        print(f"WARN  {message}")
    if not errors and not warnings:
        print("OK component metadata validated")
    return 1 if errors else 0


def main(argv: list[str]) -> int:
    root, mode, show_paths, color = parse_args(argv)
    if not root.is_dir():
        print(f"error: root not found: {root}", file=sys.stderr)
        return 1
    if mode not in MODE_SET:
        print(f"usage: {argv[0]} [root] [summary|records|legend|validate] [--paths]", file=sys.stderr)
        return 2

    dir_records = build_dir_records(root)
    script_records = build_script_records(root, dir_records)
    shell_records = build_shell_records(root)
    cmd_records = script_records + shell_records

    if mode == "records":
        print_records(dir_records, cmd_records)
        return 0
    if mode == "summary":
        print_summary(dir_records, cmd_records, show_paths, color)
        return 0
    if mode == "legend":
        print_legend(cmd_records, show_paths, color)
        return 0
    return validate(root, dir_records, script_records, shell_records)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
