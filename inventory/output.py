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
from inventory.shared import SCHEMA_VERSION, Style, group_key, matches_filters, order_key


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
    for record in sorted(
        cmd_records,
        key=lambda x: (order_key(x.get("sort_component", x["component"])), x["group"], x["source"], display_command_name(x)),
    ):
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


def render_command_group(commands: list[dict[str, str]], show_paths: bool, style: Style, indent: str = "    ") -> None:
    cmd_width = max((len(display_command_name(record)) for record in commands), default=0)
    for record in commands:
        cmd = display_command_name(record)
        cmd_text = style.wrap(cmd, style.cmd)
        padding = " " * (max(cmd_width - len(cmd), 0) + 2)
        print(f"{indent}{cmd_text}{padding}{style.wrap(record['desc'], style.desc)}")
        if show_paths:
            name = record.get("name", "").strip()
            label = f"@ {command_path(record)}"
            if name and name.lower() != cmd.lower():
                label = f"{label} [{name}]"
            print(f"{indent}  {style.wrap(label, style.desc)}")


def render_group_legend(commands: list[dict[str, str]], show_paths: bool, style: Style) -> None:
    aliases = [display_command_name(record) for record in commands]
    components = [record["component"] for record in commands]
    alias_width = max((len(alias) for alias in aliases), default=0)
    component_width = max((len(component) for component in components), default=0)
    for record in commands:
        alias = display_command_name(record)
        component = record["component"]
        alias_text = style.wrap(alias, style.cmd)
        component_text = style.wrap(f"[{component}]", style.name)
        alias_padding = " " * (max(alias_width - len(alias), 0) + 2)
        component_padding = " " * (max(component_width - len(component), 0) + 2)
        print(f"    {alias_text}{alias_padding}{component_text}{component_padding}{style.wrap(record['desc'], style.desc)}")
        if show_paths:
            name = record.get("name", "").strip()
            label = f"@ {command_path(record)}"
            if name and name.lower() != alias.lower():
                label = f"{label} [{name}]"
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

    selected = [record for record in display_records(cmd_records) if is_legend_eligible(record) and matches_filters(record, filters)]
    valid_aliases = {cmd["alias"] for cmd in valid_commands(selected)}
    filtered_records: list[dict[str, str]] = []
    for record in selected:
        if display_command_name(record) not in valid_aliases:
            continue
        filtered_records.append(record)

    grouped = group_commands(filtered_records)
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
    selected = [record for record in display_records(cmd_records) if is_legend_eligible(record) and matches_filters(record, filters)]
    valid_aliases = {cmd["alias"] for cmd in valid_commands(selected)}
    filtered_records: list[dict[str, str]] = []
    for record in selected:
        if display_command_name(record) not in valid_aliases:
            continue
        filtered_records.append(record)

    grouped = group_commands(filtered_records)
    for group in sorted(grouped, key=group_key):
        print(style.wrap(group, style.bold, style.hdr))
        commands = sorted(
            grouped[group],
            key=lambda record: (order_key(record.get("sort_component", record["component"])), display_command_name(record)),
        )
        render_group_legend(commands, show_paths, style)
        print()


def print_index(cmd_records: list[dict[str, str]], filters: list[str]) -> None:
    records = []
    for record in display_records(cmd_records):
        if not matches_filters(record, filters):
            continue
        records.extend(valid_commands([record]))
    print(json.dumps({"commands": records}, indent=2))


def print_shell(cmd_records: list[dict[str, str]], filters: list[str]) -> None:
    seen_aliases: set[str] = set()
    selected = sorted(
        cmd_records,
        key=lambda x: (group_key(x["group"]), order_key(x.get("sort_component", x["component"])), display_command_name(x)),
    )
    for record in selected:
        if record.get("source") != "script":
            continue
        if not is_legend_eligible(record) or not matches_filters(record, filters):
            continue
        alias = display_command_name(record)
        if not alias or alias in seen_aliases:
            continue
        seen_aliases.add(alias)
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
