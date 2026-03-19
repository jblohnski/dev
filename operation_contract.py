#!/usr/bin/env python3
"""Minimal validator for the dev operation object."""

from __future__ import annotations

from typing import Any, Mapping


OPERATION_TYPES = {"command", "function", "script", "binary"}
TOP_LEVELS = {"shell", "dev"}
RUN_TYPES = {"user", "sudo", None}
SOURCE_TYPES = {"script", "shell", "binary", None}


def is_valid(op: Mapping[str, Any]) -> bool:
    if not isinstance(op, Mapping):
        return False

    if not _non_empty_string(op.get("key")):
        return False
    if not _non_empty_string(op.get("path_key")):
        return False
    if op.get("top_level") not in TOP_LEVELS:
        return False
    if not _non_empty_string(op.get("component_id")):
        return False
    if op.get("operation_type") not in OPERATION_TYPES:
        return False
    if not _non_empty_string(op.get("name")):
        return False
    if not _non_empty_string(op.get("entry")):
        return False
    if not _non_empty_string(op.get("path")):
        return False
    if not _non_empty_string(op.get("taxonomy_key")):
        return False
    if not _string_list(op.get("taxonomy_path")):
        return False
    if not _non_empty_string(op.get("desc")):
        return False

    if "group" in op and op["group"] is not None and not _non_empty_string(op["group"]):
        return False
    if op.get("run") not in RUN_TYPES:
        return False
    if "keywords" in op and not _string_list(op["keywords"]):
        return False
    if "alias" in op and op["alias"] is not None and not _non_empty_string(op["alias"]):
        return False
    if op.get("source") not in SOURCE_TYPES:
        return False
    if "declared_taxonomy" in op and op["declared_taxonomy"] is not None and not _non_empty_string(op["declared_taxonomy"]):
        return False

    return True


def _non_empty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _string_list(value: Any) -> bool:
    return isinstance(value, list) and all(_non_empty_string(item) for item in value)
