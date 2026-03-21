from __future__ import annotations

import re
import shlex
import sys
from pathlib import Path


MD_META_RE = re.compile(r"^<!-- @\s*([a-z]+):\s*(.*?)\s*-->$")
MD_COMPONENT_RE = re.compile(r"^<!--\s*dev-component:\s*(.*?)\s*-->$")
SH_META_RE = re.compile(r"^#\s*@([a-z]+)(?::\s*(.*?)\s*|\s+(.+?)\s*)?$")
SH_COMMAND_RE = re.compile(r"^#\s*dev-cmd:\s*(.*?)\s*$")
SECTION_RE = re.compile(r"^##\s+(.+?)\s*$")
LEGEND_RE = re.compile(r"^#\s*([A-Za-z0-9_.-]+):\s+(.+?)\s*$")
ALIAS_RE = re.compile(r"^alias\s+([A-Za-z0-9_.-]+)=")
FUNC_RE = re.compile(r"^([A-Za-z0-9_]+)\s*\(\)\s*\{")

EXCLUDED_PARTS = {".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build", "target"}
VALID_KINDS = {"component", "subcomponent", "support"}
VALID_RUN = {"user", "sudo"}
VALID_GROUPS = {"sys", "audit", "net"}
TOP_LEVEL_SCOPES = {"shell", "dev"}
DEFAULT_ROOT = Path.home() / "dev"
MODE_SET = {"summary", "records", "legend", "validate", "index", "catalog", "manifest"}
SCHEMA_VERSION = "1.1.0"
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
COMPONENT_ORDER = ["bootstrap", "audit", "ops", "apps", "dev", "projects", "proposals", "zlogs", "arkenfox"]
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
        self.cmd = "\033[1;97m" if enabled else ""
        self.name = "\033[38;5;114m" if enabled else ""
        self.desc = "\033[2;38;5;248m" if enabled else ""
        self.accent = "\033[38;5;109m" if enabled else ""

    def wrap(self, text: str, *codes: str) -> str:
        prefix = "".join(code for code in codes if code)
        if not self.enabled or not prefix:
            return text
        return f"{prefix}{text}{self.reset}"


def parse_args(argv: list[str]) -> tuple[Path, str, bool, bool, list[str]]:
    root = DEFAULT_ROOT
    mode = "summary"
    show_paths = False
    color = sys.stdout.isatty()
    filters: list[str] = []

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
        first = clean_args.pop(0)
        if first in MODE_SET:
            mode = first
        else:
            root = Path(first).expanduser()
            if clean_args and clean_args[0] in MODE_SET:
                mode = clean_args.pop(0)
    if clean_args:
        filters = clean_args
    return root, mode, show_paths, color, filters


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
        component_match = MD_COMPONENT_RE.match(line.strip())
        if component_match:
            meta.update(parse_inline_fields(component_match.group(1), aliases={"id": "component"}))
            continue
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


def parse_md_doc(readme: Path) -> str:
    lines: list[str] = []
    capture = False
    for line in readme.read_text(errors="ignore").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("<!--"):
            if capture and lines:
                break
            continue
        if stripped.startswith("#"):
            if capture and lines:
                break
            continue
        capture = True
        lines.append(stripped)
    return " ".join(lines)


def parse_sh_meta(script: Path) -> dict[str, str]:
    meta: dict[str, str] = {}
    for line in script.read_text(errors="ignore").splitlines():
        command_match = SH_COMMAND_RE.match(line.rstrip())
        if command_match:
            meta.update(parse_inline_fields(command_match.group(1)))
            continue
        match = SH_META_RE.match(line.rstrip())
        if match:
            value = match.group(2) if match.group(2) is not None else match.group(3)
            meta[match.group(1)] = value or ""
        elif meta and line.strip() and not line.startswith("#"):
            break
    return meta


def meta_keywords(meta: dict[str, str], fallback: str = "") -> str:
    return meta.get("keywords") or meta.get("tags") or fallback


def parse_inline_fields(raw: str, aliases: dict[str, str] | None = None) -> dict[str, str]:
    fields: dict[str, str] = {}
    alias_map = aliases or {}
    for token in shlex.split(raw):
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        key = alias_map.get(key, key)
        fields[key] = value
    return fields


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


def matches_filters(record: dict[str, str], filters: list[str]) -> bool:
    if not filters:
        return True
    haystack = " ".join(
        [
            record.get("component", ""),
            record.get("group", ""),
            record.get("name", ""),
            record.get("cmd", ""),
            record.get("keywords", ""),
            record.get("desc", ""),
            record.get("path", ""),
        ]
    ).lower()
    return all(token.lower() in haystack for token in filters)


def split_rel_parts(rel: str) -> list[str]:
    if rel in {"", "."}:
        return []
    return [part for part in rel.split("/") if part]


def node_key(record: dict[str, str]) -> str:
    if record["type"] == "dir":
        return f'dir:{record["path"]}'
    cmd = record.get("cmd", record.get("alias") or record.get("name") or "")
    return f'cmd:{record["path"]}#{cmd}'


def parse_taxonomy_meta(raw: str) -> list[str]:
    if not raw.strip():
        return []
    normalized = raw.replace(">", "/")
    return [part.strip() for part in normalized.split("/") if part.strip()]


def short_token(value: str) -> str:
    parts = [part for part in re.split(r"[^A-Za-z0-9]+", value.lower()) if part]
    if not parts:
        return "x"
    if len(parts) == 1:
        return parts[0][0]
    return "".join(part[0] for part in parts)


def short_taxonomy_key(parts: list[str]) -> str:
    return ".".join(short_token(part) for part in parts)
