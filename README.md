<!-- dev-component: id=dev kind=component group=sys desc="Personal machine automation and diagnostics workspace" -->

# dev

Personal machine automation and diagnostics repo for `~/dev`.

This `README.md` is the repo-level source of truth.
If a top-level file is not source, config, schema, or this README, it probably does not belong here.

## Layout

- `bootstrap/`: tracked shell and machine bootstrap files
- `audit/`: evidence collection, Zeek workflows, and reports
- `ops/`: live system actions and operational checks
- `inventory/`: discovery, validation, and rendering modules
- `logs/`: consolidated runtime logs for declared commands
- `zlogs/`: legacy Zeek log staging fallback
- `projects/`, `proposals/`, `arkenfox/`: supporting workspace material outside the main command surface

Rule of thumb:

- put live-action tooling in `ops/`
- put collection and comparison flows in `audit/`
- put self-contained utilities under the owning component tree
- keep shell wrappers thin in `bootstrap/shell/`
- keep runtime artifacts and generated reports out of tracked source, under `logs/` when they need a repo-local home
- keep unowned personal convenience commands out of the public command surface

## Working Model

The repo is a recursive component tree with one shared command stream.

- directories declare identity through `README.md` metadata
- executable scripts and shell wrappers declare commands through `dev-cmd` metadata
- `summary`, `legend`, `validate`, and `manifest` derive from the same inventory walk
- components and subcomponents may own commands
- support directories stay documented but should not become a second command layer

`dev/` itself is workspace root metadata, not a dumping ground for standalone tools.

## Metadata

Directory identity:

```md
<!-- dev-component: id=stable-component-id kind=component|subcomponent|support group=sys|audit|net desc="one-line summary" -->
```

Command metadata:

```bash
# dev-cmd: alias=token name=terse-token group=sys|audit|net run=user|sudo tags="tag-one tag-two" legend=hide desc="one-line summary"
```

Kinds:

- `component`: first-class owner in summary ordering
- `subcomponent`: nested owner under a component
- `support`: documented directory without primary command ownership

Rules:

- commands attach to the nearest explicit `component` or `subcomponent`
- `alias` is the exact interactive command token
- `name` is a terse no-space/no-dot identifier, not a formal label
- public command names should contain the exact alias, usually as the whole name or a prefix
- command location is derived from the script or shell file path
- every command object exposes `path_key` (`path#alias`) and `ref` (`scope/component/group/name`)
- groups are fixed and explicit: `sys`, `audit`, `net`
- tags/keywords are short space-delimited words for lightweight taxonomy
- if a discovered record does not resolve to a real alias, it does not belong in `legend`
- if a command is just an ad hoc launcher for something outside this repo, it does not belong in `legend`
- deeper tree structure is allowed, but human views stay group-first and shallow

## Inventory

`component-scan.sh` is the shared inventory entrypoint.

Human-first outputs:

- `summary`: group-first component view
- `legend`: terse command list
- `validate`: metadata and command-contract checks

Machine outputs:

- `manifest`: full tree and command payload
- `index`: compact command list used by consumers that only need runnable commands
- `shell`: alias publication feed for script-backed commands

Typical use:

```bash
python3 ./component-scan.sh summary
python3 ./component-scan.sh legend
python3 ./component-scan.sh validate
python3 ./component-scan.sh manifest
```

`devdash` is now a machine-status dashboard, not a command browser.

Keep the contract small:

- human-facing command identity is `alias`, `name`, `path`, `path_key`, `ref`, `run`, `desc`, `group`
- `legend` displays alias, name, and description; `--paths` adds the implementation location
- shell publishing should come from scan output, not handwritten alias duplication
- inventory is there to describe the tree, not create a second bureaucracy around it
- public commands should express durable repo-owned capability, not personal one-off launch shortcuts

## Shell

Tracked shell profile source of truth:

- `bootstrap/.zshrc`

Interactive shell init does two things:

- loads the handwritten helpers from `bootstrap/shell/*.sh`
- publishes discovered script commands from inventory scan output

Main helpers:

- `comp`: summary/legend/validate/manifest/dashboard entrypoint
- `ds`: summary
- `dl`: legend
- `dv`: validate
- `dd`: machine status dashboard
- `am`, `as`, `ar`: compact audit monitor/status/report aliases

Publish shell changes with:

```bash
pz
```

## Audit And Zeek

The audit stack auto-ingests Zeek logs when available.
Primary location is `logs/zeek/`.
Legacy fallbacks are `audit/zlogs/`, `zlogs/`, and `~/zlogs/`.
Reports are written under `audit/report/zeek/`.

Useful entrypoints:

```bash
audit
as
am current
ar
am zeek --top 10
am start en0
am logs --last 30m --top 5
sysclean --yes
```

## Conventions

- prefer small standalone scripts with clear metadata headers
- use existing tools when they fit: `python3`, `rg`, `tcpdump`, `zeek`, `lnav`
- avoid extra wrapper layers when a direct script entrypoint is enough
- keep repo docs centralized here unless a subdirectory truly needs its own local README
