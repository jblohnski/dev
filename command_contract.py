#!/usr/bin/env python3
"""Minimal validator for the dev command object."""

from __future__ import annotations

from typing import Any, Mapping


RUN_TYPES = {"user", "sudo", None}
SOURCE_TYPES = {"script", "shell", None}


def is_valid(cmd: Mapping[str, Any]) -> bool:
    if not isinstance(cmd, Mapping):
        return False

    if not _non_empty_string(cmd.get("path")):
        return False
    if not _non_empty_string(cmd.get("source_path")):
        return False
    if not _non_empty_string(cmd.get("component")):
        return False
    if not _non_empty_string(cmd.get("alias")):
        return False
    if not _non_empty_string(cmd.get("name")):
        return False
    if not _non_empty_string(cmd.get("desc")):
        return False

    if "group" in cmd and cmd["group"] is not None and not _non_empty_string(cmd["group"]):
        return False
    if cmd.get("run") not in RUN_TYPES:
        return False
    if cmd.get("source") not in SOURCE_TYPES:
        return False
    if "keywords" in cmd and not _string_list(cmd["keywords"]):
        return False

    return True


def _non_empty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _string_list(value: Any) -> bool:
    return isinstance(value, list) and all(_non_empty_string(item) for item in value)
