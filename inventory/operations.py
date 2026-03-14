from __future__ import annotations

from typing import Any

from operation_contract import is_valid


def operation_type_for_record(record: dict[str, str]) -> str:
    source = record.get("source", "")
    if source == "shell":
        return "function"
    if source == "script":
        return "script"
    return "command"


def record_to_operation(record: dict[str, str]) -> dict[str, Any]:
    cmd = record.get("cmd", record.get("alias") or record.get("name") or "")
    declared_taxonomy = record.get("declared_taxonomy")
    if declared_taxonomy is None and record.get("taxonomy", ""):
        declared_taxonomy = record.get("taxonomy", "").strip() or None
    return {
        "key": record.get("key", ""),
        "path_key": record.get("path_key", ""),
        "component_id": record.get("component_id", record.get("component", "")),
        "operation_type": operation_type_for_record(record),
        "name": record.get("name", "") or cmd,
        "entry": cmd,
        "path": record.get("path", ""),
        "group": record.get("group"),
        "run": record.get("run"),
        "keywords": record.get("keywords", []),
        "alias": record.get("alias"),
        "source": record.get("source"),
        "declared_taxonomy": declared_taxonomy,
        "taxonomy_key": record.get("taxonomy_key", ""),
        "taxonomy_path": record.get("taxonomy_path", []),
        "desc": record.get("desc", ""),
    }


def valid_operations(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    ops: list[dict[str, Any]] = []
    for record in records:
        op = record_to_operation(record)
        if is_valid(op):
            ops.append(op)
    return ops


def operation_command_name(op: dict[str, Any]) -> str:
    alias = op.get("alias")
    if isinstance(alias, str) and alias.strip():
        return alias
    entry = op.get("entry")
    if isinstance(entry, str) and entry.strip():
        return entry
    name = op.get("name")
    return name if isinstance(name, str) else ""
