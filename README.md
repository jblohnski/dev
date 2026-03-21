<!-- dev-component: id=dev kind=component group=sys desc="Personal machine automation and diagnostics workspace" -->

# dev

Personal machine automation and diagnostics repo for `~/dev`.

## Layout

- `bootstrap/`: tracked shell and machine bootstrap files
- `audit/`: evidence collection, Zeek workflows, and reports
- `ops/`: live system actions and operational checks
- `apps/`: standalone file-backed utilities grouped under one parent
- `inventory/`: discovery, validation, and rendering modules

Rule of thumb:

- put live-action tooling in `ops/`
- put collection and comparison flows in `audit/`
- put self-contained utilities in `apps/`
- keep shell wrappers thin in `bootstrap/shell/`

## Inventory

`component-scan.sh` is the shared source for:

- `summary`
- `legend`
- `records`
- `index`
- `manifest`
- `catalog`
- `validate`

Human views and the dashboard should not invent their own discovery logic.
They should consume the same command-reference stream.

Separation of concerns:

- `bootstrap/` initializes and publishes shell state
- `inventory/` walks `dev/` and resolves components and commands

Two things are discovered:

- components: directories with declared identity
- commands: invokable records with alias, name, desc, and simple group

Not every component is a command.

## Metadata

Directory `README.md` files declare component metadata:

```md
<!-- dev-component: id=stable-component-id kind=component|subcomponent|support group=sys|audit|net desc="one-line summary" -->
```

Executable scripts and shell wrappers declare command metadata:

```bash
# dev-cmd: alias=token name="Human Label" group=sys|audit|net run=user|sudo legend=hide desc="one-line summary"
```

The shared command-reference model keeps:

- `alias`
- `name`
- `desc`
- `group`

That is the minimum human-facing contract used to build `legend` and `devdash`.

Known groups are intentionally small:

- `sys`
- `audit`
- `net`

For human views, `alias` is the command key.
If something does not resolve to an alias, it should not appear in the legend command list.

Human-facing views should stay one level deep:

- component
- command

Deeper structure can still exist in the tree and machine outputs, but it should roll up in `legend` and `devdash`.

## Docs

- [COMPONENT_PROTOCOL.md](COMPONENT_PROTOCOL.md): primary discovery and command-reference contract
- [DISCOVERY_RULES.md](DISCOVERY_RULES.md): terse walk/extraction rules
- [INVENTORY_SCHEMA.md](INVENTORY_SCHEMA.md): manifest payload shape
- `command.schema.json`: canonical command object contract

## Shell Source

Tracked shell profile source of truth:

- `bootstrap/.zshrc`

Publish it with:

```bash
pz
```
