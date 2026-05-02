from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from inventory.commands import command_object, command_path, public_command_records
from inventory.discovery import (
    build_dir_lookup,
    catalog_item_for_cmd,
    catalog_item_for_dir,
    collect_manifest_index,
    display_command_name,
    display_records,
)
from inventory.shared import SCHEMA_VERSION, Style, group_key, matches_filters, node_key, order_key

LEGEND_DESC_WIDTH = 28
LEGEND_ALIAS_WIDTH = 4


def compact_text(value: str, limit: int) -> str:
    text = " ".join(value.split())
    if len(text) <= limit:
        return text
    clipped = text[: limit + 1].rsplit(" ", 1)[0].rstrip()
    return clipped or text[:limit].rstrip()


def render_command_group(commands: list[dict[str, str]], show_paths: bool, style: Style, indent: str = "    ") -> None:
    cmd_width = max((len(display_command_name(record)) for record in commands), default=0)
    name_width = max((len((record.get("name") or display_command_name(record)).strip()) for record in commands), default=0)
    for record in commands:
        cmd = display_command_name(record)
        name = (record.get("name") or cmd).strip()
        cmd_text = style.wrap(cmd, style.cmd)
        padding = " " * (max(cmd_width - len(cmd), 0) + 2)
        name_text = style.wrap(name, style.name)
        name_padding = " " * (max(name_width - len(name), 0) + 2)
        print(f"{indent}{cmd_text}{padding}{name_text}{name_padding}{style.wrap(record['desc'], style.desc)}")
        if show_paths:
            label = f"@ {command_path(record)}"
            print(f"{indent}  {style.wrap(label, style.desc)}")


def render_group_legend(commands: list[dict[str, str]], show_paths: bool, style: Style) -> None:
    names = [(record.get("name") or display_command_name(record)).strip().lower() for record in commands]
    name_width = max((len(name) for name in names), default=0)
    for record in commands:
        alias = display_command_name(record).lower()
        name = (record.get("name") or alias).strip().lower()
        alias_text = style.wrap(alias, style.cmd)
        alias_padding = " " * (max(LEGEND_ALIAS_WIDTH - len(alias), 0) + 1)
        name_text = style.wrap(name, style.name)
        name_padding = " " * (max(name_width - len(name), 0) + 2)
        desc = compact_text(record["desc"].lower(), LEGEND_DESC_WIDTH)
        print(f"    {alias_text}{alias_padding}{name_text}{name_padding}{style.wrap(desc, style.desc)}")
        if show_paths:
            label = f"@ {command_path(record)}"
            print(f"      {style.wrap(label, style.desc)}")


def group_commands(records: list[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    grouped: dict[str, list[dict[str, str]]] = {}
    for record in records:
        grouped.setdefault(record["group"], []).append(record)
    return grouped

def print_summary(dir_records: list[dict[str, str]], cmd_records: list[dict[str, str]], show_paths: bool, color: bool, filters: list[str]) -> None:
    style = Style(color)
    components = [record for record in dir_records if record["kind"] == "component"]
    components_by_id = {record["component"]: record for record in components}
    subcomponents = [record for record in dir_records if record["kind"] == "subcomponent"]
    subcomponents_by_parent: dict[str, list[dict[str, str]]] = {}
    for record in subcomponents:
        subcomponents_by_parent.setdefault(record["parent"], []).append(record)

    grouped = group_commands(public_command_records(cmd_records, filters))
    for group in sorted(grouped, key=group_key):
        print(style.wrap(group, style.bold, style.hdr))
        cmds_by_component: dict[str, list[dict[str, str]]] = {}
        for record in grouped[group]:
            cmds_by_component.setdefault(record["component"], []).append(record)
        visible_components = []
        for component in sorted(components, key=lambda record: order_key(record["component"])):
            component_id = component["component"]
            has_direct_commands = component_id in cmds_by_component
            has_subcomponent_commands = any(
                sub["component"] in cmds_by_component for sub in subcomponents_by_parent.get(component_id, [])
            )
            if has_direct_commands or has_subcomponent_commands:
                visible_components.append(component_id)
        for component_id in visible_components:
            component = components_by_id[component_id]
            print(
                f'  {style.wrap(component["component"], style.name)} '
                f'{style.wrap("[" + component["kind"] + "]", style.desc)} '
                f'{style.wrap(component["desc"], style.desc)}'
            )
            for sub in sorted(subcomponents_by_parent.get(component["component"], []), key=lambda x: x["component"]):
                print(
                    f'    + {style.wrap(sub["component"], style.name)} '
                    f'{style.wrap("[" + sub["kind"] + "]", style.desc)} '
                    f'{style.wrap(sub["desc"], style.desc)}'
                )
                if sub["component"] in cmds_by_component:
                    render_command_group(
                        sorted(cmds_by_component[sub["component"]], key=display_command_name),
                        show_paths,
                        style,
                        indent="      ",
                    )
            if component_id in cmds_by_component:
                render_command_group(sorted(cmds_by_component[component_id], key=display_command_name), show_paths, style)
        print()


def print_legend(cmd_records: list[dict[str, str]], show_paths: bool, color: bool, filters: list[str]) -> None:
    style = Style(color)
    print(style.wrap("commands", style.hdr))
    print()
    grouped = group_commands(public_command_records(cmd_records, filters))
    for group in sorted(grouped, key=group_key):
        print(style.wrap(group, style.bold, style.hdr))
        commands = sorted(
            grouped[group],
            key=lambda record: (order_key(record.get("sort_component", record["component"])), display_command_name(record)),
        )
        render_group_legend(commands, show_paths, style)
        print()


def print_index(cmd_records: list[dict[str, str]], filters: list[str]) -> None:
    records = [command_object(record) for record in public_command_records(cmd_records, filters)]
    print(json.dumps({"commands": records}, indent=2))


def print_shell(cmd_records: list[dict[str, str]], filters: list[str]) -> None:
    for record in public_command_records(cmd_records, filters):
        if record.get("source") != "script":
            continue
        alias = display_command_name(record)
        print(f"{alias}\t{record['path']}\t{record.get('run', 'user')}")


def print_manifest(
    root: Path,
    dir_records: list[dict[str, str]],
    script_records: list[dict[str, str]],
    shell_records: list[dict[str, str]],
    cmd_records: list[dict[str, str]],
    filters: list[str],
) -> None:
    by_rel, explicit_paths = build_dir_lookup(dir_records)
    public_records = public_command_records(cmd_records, filters)
    public_keys = {node_key(record) for record in public_records}
    public_order = {node_key(record): index for index, record in enumerate(public_records, start=1)}
    emitted_cmd_records = [record for record in display_records(cmd_records) if matches_filters(record, filters)]
    items: list[dict[str, object]] = []

    for record in dir_records:
        if record["kind"] == "support" and filters and not matches_filters(record, filters):
            continue
        items.append(catalog_item_for_dir(record, by_rel))

    for record in emitted_cmd_records:
        key = node_key(record)
        items.append(
            catalog_item_for_cmd(
                record,
                by_rel,
                explicit_paths,
                legend_visible=key in public_keys,
                display_order=public_order.get(key),
            )
        )

    items.sort(key=lambda item: (str(item["taxonomy_key"]), str(item["path_key"])))

    payload = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "root": str(root),
        "index": collect_manifest_index(
            root,
            dir_records,
            script_records,
            shell_records,
            emitted_cmd_records,
            len(public_records),
            len(items),
        ),
        "items": items,
    }
    print(json.dumps(payload, indent=2))
