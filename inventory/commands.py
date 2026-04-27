from __future__ import annotations

from typing import Any

from command_contract import is_valid
from inventory.discovery import display_command_name, is_legend_eligible
from inventory.shared import group_key, matches_filters, order_key


def command_path(record: dict[str, str]) -> str:
    alias = display_command_name(record)
    return f"{record.get('path', '')}#{alias}"


def command_object(record: dict[str, Any]) -> dict[str, Any]:
    alias = display_command_name(record)
    return {
        "alias": alias,
        "name": record.get("name", "") or alias,
        "path": record.get("path", ""),
        "run": record.get("run", "user"),
        "desc": record.get("desc", ""),
        "group": record.get("group"),
    }


def command_sort_key(record: dict[str, Any]) -> tuple[tuple[int, str], tuple[int, str], str]:
    return (
        group_key(record.get("group", "")),
        order_key(record.get("sort_component", record.get("component", ""))),
        display_command_name(record),
    )


def public_command_records(records: list[dict[str, Any]], filters: list[str] | None = None) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    seen_aliases: set[str] = set()
    active_filters = filters or []
    for record in sorted(records, key=command_sort_key):
        alias = (record.get("alias") or "").strip()
        if not alias or alias in seen_aliases:
            continue
        if not is_legend_eligible(record):
            continue
        if not matches_filters(record, active_filters):
            continue
        if not is_valid(command_object(record)):
            continue
        seen_aliases.add(alias)
        selected.append(record)
    return selected
