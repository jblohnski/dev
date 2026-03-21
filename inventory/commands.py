from __future__ import annotations

from typing import Any

from command_contract import is_valid
from inventory.discovery import display_command_name


def command_path(record: dict[str, str]) -> str:
    alias = display_command_name(record)
    return f"{record.get('path', '')}#{alias}"


def runtime_command_object(record: dict[str, Any]) -> dict[str, Any]:
    alias = display_command_name(record)
    return {
        "path": command_path(record),
        "source_path": record.get("path", ""),
        "component": record.get("component", ""),
        "group": record.get("group"),
        "alias": alias,
        "name": record.get("name", "") or alias,
        "desc": record.get("desc", ""),
        "run": record.get("run"),
        "source": record.get("source"),
    }


def command_object(record: dict[str, Any]) -> dict[str, Any]:
    alias = display_command_name(record)
    return {
        "alias": alias,
        "name": record.get("name", "") or alias,
        "desc": record.get("desc", ""),
        "group": record.get("group"),
    }


def valid_commands(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    commands: list[dict[str, Any]] = []
    seen_aliases: set[str] = set()
    for record in records:
        cmd = command_object(record)
        if not is_valid(cmd):
            continue
        if cmd["alias"] in seen_aliases:
            continue
        seen_aliases.add(cmd["alias"])
        commands.append(cmd)
    return commands
