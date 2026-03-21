#!/usr/bin/env python3
"""Minimal validator for the dev command object."""

from __future__ import annotations

from typing import Any, Mapping


def is_valid(cmd: Mapping[str, Any]) -> bool:
    if not isinstance(cmd, Mapping):
        return False

    if not _non_empty_string(cmd.get("alias")):
        return False
    if not _non_empty_string(cmd.get("name")):
        return False
    if not _non_empty_string(cmd.get("desc")):
        return False
    if not _non_empty_string(cmd.get("group")):
        return False

    return True


def _non_empty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())
