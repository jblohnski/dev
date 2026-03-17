# component protocol

This repo treats `~/dev` as a recursive component tree with one shared command-reference stream.

Related documents:

- `DISCOVERY_RULES.md`: terse walk/extraction rules
- `INVENTORY_SCHEMA.md`: manifest payload shape

## core intent

- `README.md` metadata establishes directory identity.
- script and shell metadata establish discoverable commands.
- `legend`, `summary`, `index`, and `devdash` should all derive from the same normalized command references.

There are two distinct inventories:

- components: discovered containers rooted in the tree
- commands: the invokable subset discovered from script and shell declarations

Not every component is a command.

## layout rules

- `bootstrap/`: tracked environment bootstrap state
- `audit/`: evidence collection and reporting workflows
- `ops/`: live system actions and checks
- `apps/`: standalone file-backed utilities
- `inventory/`: discovery, validation, and rendering modules

`dev/` itself is workspace root metadata, not the place to accumulate standalone tools.

## directory rules

Declare directory identity near the top of `README.md`:

```md
<!-- @component: stable-component-id -->
<!-- @kind: component|subcomponent|support -->
<!-- @desc: one-line summary -->
<!-- @keywords: space-delimited keywords -->
<!-- @taxonomy: optional semantic lineage -->
```

Interpretation:

- `component`: first-class owner in summary/legend ordering
- `subcomponent`: nested first-class unit under a component
- `support`: documented directory that should not own the primary command surface

Commands attach to the nearest explicit ancestor whose kind is `component` or `subcomponent`.

## command rules

Discoverable commands need this metadata:

```bash
# @name: human label
# @desc: one-line summary
# @cmd: preferred invocation token
# @keywords: space-delimited keywords
# @taxonomy: optional semantic lineage
# @run: user|sudo
```

The minimum shared command-reference fields are:

- `path`
- `alias`
- `name`
- `desc`

Interpretation:

- `path`: unique declaration path, typically `source-path#alias`
- `alias`: required displayed invocation token used by human-facing views
- `name`: fuller human label
- `desc`: terse summary
- `source_path`: backing file path retained in the command contract

`@tags` remains a legacy alias for `@keywords`.

For human-facing command views, `alias` is the canonical entry key.
If a discovered record does not resolve to an alias, it is not a legit legend command.

## grouping rules

- file-backed scripts use structure first when they live in a real subdirectory under their owner
- file-backed scripts fall back to keyword-derived grouping when they live directly at the owner root
- shell wrappers group by shell section plus declared subgroup keywords
- keywords are secondary facets, not the primary navigation tree

This keeps `apps/netshot`, `apps/sitechk`, and `apps/wifiscan` grouped structurally while still allowing root-level audit scripts to fall into `zeek` or `macos`.

Human-facing views should remain one level deep in perspective:

- component list first
- command list under the component
- deeper nested directories roll up to the owning component for legend/dashboard purposes

## shell wrapper rules

- discover from `bootstrap/shell/*.sh`
- `## section` establishes shell scope
- bare `# @component` resets metadata to the current section owner
- wrappers should stay thin and point at file-backed functionality when practical

Canonical shell sections:

- `bootstrap`
- `audit`
- `dev`
- `python`
- `nav`
- `git`
- `network`
- `dns`
- `util`

## output rules

- `summary` and `legend` are terse human projections
- `index` is the shared machine-readable command list
- `manifest` and `catalog` emit the richer JSON inventory payload
- `validate` enforces metadata shape and command legitimacy

Command-facing outputs should be grounded in the command contract defined by `command.schema.json` and `command_contract.py`.
The broader operation contract can remain available for richer manifest/catalog use, but it is no longer the canonical legend/index model.
