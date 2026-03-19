from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from inventory.commands import command_object, command_path, valid_commands
from inventory.discovery import (
    build_dir_lookup,
    catalog_item_for_cmd,
    catalog_item_for_dir,
    collect_manifest_index,
    display_command_name,
    display_records,
    is_legend_eligible,
)
from inventory.shared import SCHEMA_VERSION, Style, matches_filters, order_key


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
    for record in sorted(cmd_records, key=lambda x: (order_key(x["component"]), x["group"], x["source"], display_command_name(x))):
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


def render_command_group(commands: list[dict[str, str]], show_paths: bool, style: Style) -> None:
    cmd_width = max((len(display_command_name(record)) for record in commands), default=0)
    for record in commands:
        cmd = display_command_name(record)
        cmd_text = style.wrap(cmd, style.cmd)
        padding = " " * (max(cmd_width - len(cmd), 0) + 2)
        print(f"    {cmd_text}{padding}{style.wrap(record['desc'], style.desc)}")
        if show_paths:
            name = record.get("name", "").strip()
            label = f"@ {command_path(record)}"
            if name and name.lower() != cmd.lower():
                label = f"{label} [{name}]"
            print(f"      {style.wrap(label, style.desc)}")

def print_summary(dir_records: list[dict[str, str]], cmd_records: list[dict[str, str]], show_paths: bool, color: bool, filters: list[str]) -> None:
    style = Style(color)
    components = [record for record in dir_records if record["kind"] == "component" and record["rel"] != "."]
    if any(record["rel"] == "." for record in dir_records):
        root_record = next(record for record in dir_records if record["rel"] == ".")
        components = [root_record] + sorted(components, key=lambda x: order_key(x["component"]))
    else:
        components = sorted(components, key=lambda x: order_key(x["component"]))
    subcomponents = [record for record in dir_records if record["kind"] == "subcomponent"]

    selected = [record for record in display_records(cmd_records) if matches_filters(record, filters)]
    valid_paths = {cmd["path"] for cmd in valid_commands(selected)}
    cmds_by_component: dict[str, list[dict[str, str]]] = {}
    for record in selected:
        if command_path(record) not in valid_paths:
            continue
        if matches_filters(record, filters):
            cmds_by_component.setdefault(record["component"], []).append(record)

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
        grouped: dict[str, list[dict[str, str]]] = {}
        for record in cmds_by_component.get(component["component"], []):
            grouped.setdefault(record["group"], []).append(record)
        for group in sorted(grouped):
            print(f"  > {style.wrap(group, style.accent)}")
            render_command_group(grouped[group], show_paths, style)
        print()


def print_legend(cmd_records: list[dict[str, str]], show_paths: bool, color: bool, filters: list[str]) -> None:
    style = Style(color)
    print(style.wrap("commands", style.hdr))
    print()
    grouped_by_component: dict[str, list[dict[str, str]]] = {}
    selected = [record for record in display_records(cmd_records) if is_legend_eligible(record) and matches_filters(record, filters)]
    valid_paths = {cmd["path"] for cmd in valid_commands(selected)}
    for record in selected:
        if command_path(record) not in valid_paths:
            continue
        grouped_by_component.setdefault(record["component"], []).append(record)

    for component in sorted(grouped_by_component, key=order_key):
        print(style.wrap(component, style.bold, style.hdr))
        commands = sorted(grouped_by_component[component], key=display_command_name)
        render_command_group(commands, show_paths, style)
        print()


def print_index(cmd_records: list[dict[str, str]], filters: list[str]) -> None:
    records = []
    for record in display_records(cmd_records):
        if not matches_filters(record, filters):
            continue
        records.extend(valid_commands([record]))
    print(json.dumps({"commands": records}, indent=2))


def print_manifest(
    root: Path,
    dir_records: list[dict[str, str]],
    script_records: list[dict[str, str]],
    shell_records: list[dict[str, str]],
    cmd_records: list[dict[str, str]],
    filters: list[str],
) -> None:
    by_rel, explicit_paths = build_dir_lookup(dir_records)
    emitted_cmd_records = [record for record in display_records(cmd_records) if matches_filters(record, filters)]
    items: list[dict[str, object]] = []

    for record in dir_records:
        if record["kind"] == "support" and filters and not matches_filters(record, filters):
            continue
        items.append(catalog_item_for_dir(record, by_rel))

    for record in emitted_cmd_records:
        items.append(catalog_item_for_cmd(record, by_rel, explicit_paths))

    items.sort(key=lambda item: (str(item["taxonomy_key"]), str(item["path_key"])))

    payload = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "root": str(root),
        "index": collect_manifest_index(root, dir_records, script_records, shell_records, emitted_cmd_records, len(items)),
        "items": items,
    }
    print(json.dumps(payload, indent=2))
