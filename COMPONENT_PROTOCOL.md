# component protocol

This repo treats `~/dev` as a recursive component tree.

related documents:

- `DISCOVERY_RULES.md`: terse tree walk and extraction rules
- `INVENTORY_SCHEMA.md`: manifest object shape

## intent

- A directory becomes an explicit component when its `README.md` declares component metadata.
- Runnable scripts become discoverable commands when they declare command metadata.
- Shell legend commands and `devdash` should consume one shared inventory stream instead of re-implementing discovery.

## canonical taxonomy

Inventory should adhere to one canonical hierarchy:

1. `component`
2. `group`
3. `command`

canonical record fields:

- `type`: `dir` | `cmd`
- `source`: `readme` | `script` | `shell`
- `path`: repo-relative path to the source file or directory
- `component`: owning component id
- `group`: display subgroup inside the owning component
- `name`: human-facing command label when `type=cmd`
- `cmd`: command token shown in legends and used by shell-backed records
- `run`: `user` | `sudo` when `type=cmd`
- `keywords`: taxonomy keywords
- `desc`: one-line summary

canonical json catalog fields:

- `key`: short taxonomic handle such as `n.s`
- `path_key`: canonical unique structural key
- `declared_taxonomy`: raw metadata taxonomy when present
- `taxonomy_source`: `explicit` or `derived`
- `taxonomy_key`: verbose semantic lineage key
- `taxonomy_path`: lineage segments as an ordered array
- `docs_path`: nearest README path

Canonical operation object:

- see `operation.schema.json`
- validate with `operation_contract.py:is_valid(op)`
- `operation` is the broad executable parent for commands, functions, scripts, and binaries

interpretation rules:

- `component` is the stable owner used for merged output.
- `group` is the human-facing subgroup used by `l` and `devdash`.
- `path` is always preserved in machine output and richer dashboards, even when terse legends omit it.

## readme metadata

Declare component identity near the top of `README.md` with HTML comments:

```md
<!-- @component: audit -->
<!-- @kind: component -->
<!-- @desc: Quick macOS audit and Zeek analysis pipeline -->
<!-- @keywords: audit macos zeek -->
```

fields:

- `@component`: stable component id
- `@kind`: `component` | `subcomponent` | `support`
- `@desc`: one-line summary used in rollups
- `@keywords`: space-separated taxonomy keywords
- `@taxonomy`: optional explicit semantic lineage such as `net/scan`

rules:

- `component`: top-level or independently meaningful unit
- `subcomponent`: nested unit with distinct responsibility
- `support`: content directory that should be visible but not treated as a primary control surface
- Every tracked directory with a `README.md` should eventually declare explicit metadata.
- `@taxonomy` is optional and may be used to decouple semantic lineage from directory names.

If a `README.md` exists without metadata, discovery may still show the directory as implicit support, but it is not a first-class component.

## script metadata

runnable scripts should declare:

```bash
# @name: human label
# @desc: one-line description
# @cmd: command token shown in legends
# @keywords: space-separated taxonomy keywords
# @taxonomy: optional semantic lineage such as net/scan
# @run: user|sudo
```

optional:

```bash
# @alias: shortname
# @owner: firstparty
```

rules:

- `@name`, `@desc`, and `@cmd` form the canonical command triplet.
- `@desc` is required for dashboard inclusion.
- `@run` controls invocation mode in dashboards.
- `@keywords` is expected and drives taxonomy grouping.
- `@taxonomy` is optional and overrides derived taxonomy when present.
- `@alias` is display metadata only; it does not create shell aliases automatically.
- `@tags` is accepted as a legacy alias for `@keywords`.
- Executable scripts in tracked components are expected to declare all core metadata fields.

## shell metadata

shell command wrappers remain valid inventory, but they should be thin wrappers around file-backed functionality whenever possible.

rules:

- Shell legend commands are discovered from `bootstrap/shell/*.sh`.
- `## section` headers define shell groups.
- `# @component` on its own resets shell metadata to the current section owner.
- Shell commands should declare `@name`, `@desc`, `@cmd`, and `@keywords` before the alias or function they describe.
- Legacy `# name: description` lines are still parsed while older wrappers are migrated.
- Canonical shell sections are:
  - `bootstrap`
  - `audit`
  - `dev`
  - `python`
  - `nav`
  - `git`
  - `network`
  - `dns`
  - `util`

## discovery contract

The shared scanner walks `~/dev` recursively and emits records for:

- explicit components and subcomponents from `README.md`
- implicit support directories that have a `README.md` but no metadata
- runnable scripts with script metadata
- shell aliases/functions discovered from `bootstrap/shell/*.sh`

Each script record is attached to the nearest explicit ancestor component; if none exists, it falls back to the top-level directory name.

## output shapes

human summary:

- terse tree-style stdout for quick review
- components first, groups second, commands third

machine records:

- tab-separated records for dashboards and generators
- one record type per line: `dir` or `cmd`

machine catalog:

- `./component-scan.sh manifest`
- `./component-scan.sh catalog`
- emits the canonical JSON info object described by the plain JSON contract in `inventory.schema.json`
- `key` is shorthand; `path_key` is the authoritative unique identifier
- legend and index command views should be derived from valid operation objects

validation:

- `./component-scan.sh validate`
- flags missing metadata, invalid kinds, invalid run modes, duplicate component ids, and non-canonical shell sections

This is the source of truth for `devdash`, `l`, and related inventory views.
