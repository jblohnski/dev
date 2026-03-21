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
<!-- dev-component: id=stable-component-id kind=component|subcomponent|support group=sys|audit|net desc="one-line summary" -->
```

Interpretation:

- `component`: first-class owner in summary/legend ordering
- `subcomponent`: nested first-class unit under a component
- `support`: documented directory that should not own the primary command surface

Commands attach to the nearest explicit ancestor whose kind is `component` or `subcomponent`.

## command rules

Discoverable commands need this metadata:

```bash
# dev-cmd: alias=token name="Human Label" group=sys|audit|net run=user|sudo legend=hide desc="one-line summary"
```

The minimum shared command-reference fields are:

- `alias`
- `name`
- `desc`
- `group`

Interpretation:

- `alias`: required invocation token used by human-facing views
- `name`: fuller human label
- `desc`: terse summary
- `group`: one of `sys`, `audit`, or `net`

For human-facing command views, `alias` is the canonical entry key.
If a discovered record does not resolve to an alias, it is not a legit legend command.

## grouping rules

- grouping is explicit in metadata, not inferred from keywords
- allowed groups are fixed: `sys`, `audit`, `net`
- component and command metadata should declare one of those groups directly

Human-facing views should remain one level deep in perspective:

- group list first
- component list under a group when structural context is needed
- command list under the group or component
- deeper nested directories roll up to the owning component for human-facing views

## shell wrapper rules

- discover from `bootstrap/shell/*.sh`
- `## section` establishes shell scope
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
