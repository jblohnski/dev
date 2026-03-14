<!-- @component: dev -->
<!-- @kind: component -->
<!-- @desc: Personal machine automation and diagnostics workspace -->
<!-- @keywords: workspace automation diagnostics -->

# dev

Personal machine automation and diagnostics repo for `~/dev`.

## Taxonomy (phase 1)

Top-level groups are intentionally separated by lifecycle:

1. `bootstrap/`:
   Files used to initialize or publish local environment/profile state.
   Example: shell profile, terminal profiles, git/editor defaults.
2. `ops/`:
   Operational scripts that interrogate, harden, or manipulate live system state.
   Example: router checks, macOS hardening, Firefox hardening.
3. `audit/`:
   Analysis pipeline that captures snapshots, compares baseline vs current, and reports findings.
4. `ops/pf/`:
   PF-specific firewall toolkit and related privileged/network policy helpers.
5. `arkenfox/`:
   Upstream/vendor material and related support scripts.
6. `projects/`:
   Independent project sandboxes, excluded from this repo workflow.
7. `wifiscan/`:
   Native Wi-Fi scan component backed by CoreWLAN for modern macOS where `airport` is no longer dependable.

## Shell Profile Source of Truth

Canonical tracked shell profile path:

- `bootstrap/.zshrc`

Publish workflow:

```bash
pz
```

`pz` links `~/dev/bootstrap/.zshrc` into `~/.zshrc` and reloads it in the current shell, so shell updates apply by reference. `pzcp` is available as a copy fallback.

## Ops vs Audit

- `ops/`: direct actions and runtime interrogation.
- `audit/`: evidence collection + normalization + reporting.

Rule: keep scripts that *act* in `ops/`; keep scripts that *measure/compare* in `audit/`.

## Zeek Integration

See [DEV_AUDIT_ZEEK_INTEGRATION.md](DEV_AUDIT_ZEEK_INTEGRATION.md) for the integrated Zeek datamining workflow, anchor-based investigation model (`uid` or `src/dst/port/timestamp`), and artifact structure.

Capture logs with the tracked wrapper in `audit/zeek-capture.sh`; it starts Zeek with `-C` and `Log::default_logdir=$ZEEK_LOG_DIR` so `audit.sh` and `zeek-audit.sh` read from a predictable log directory.

## Metadata Convention (for legend/dashboard)

Allowed component tags in `README.md` headers:

```md
<!-- @component: stable-component-id -->
<!-- @kind: component|subcomponent|support -->
<!-- @desc: one-line summary -->
<!-- @keywords: space-delimited taxonomy keywords -->
<!-- @taxonomy: optional semantic lineage such as net/scan -->
```

Allowed command tags in executable scripts:

```bash
# @name: human label
# @desc: one-line summary
# @cmd: command name shown in legend
# @keywords: space-delimited taxonomy keywords
# @taxonomy: optional semantic lineage such as net/scan
# @run: user|sudo
```

Allowed command tags in `bootstrap/shell/*.sh`:

```bash
# @component
# @name: human label
# @desc: one-line summary
# @cmd: command name shown in legend
# @keywords: space-delimited taxonomy keywords
# @taxonomy: optional semantic lineage such as net/scan
# @run: user|sudo
```

Rules:

- `@component` on its own resets shell metadata to the current section owner.
- `@keywords` is expected for discoverable commands and components.
- The canonical command triplet is `name`, `desc`, `cmd`.
- Legend output and `devdash` both consume that triplet.
- Command grouping is derived from declared keywords, not from ad hoc display comments.
- `@tags` is treated as a legacy alias for `@keywords` while older files are cleaned up.

Directory components can declare explicit metadata in `README.md` comment headers. See [COMPONENT_PROTOCOL.md](COMPONENT_PROTOCOL.md).

Shared inventory entrypoint:

- `./component-scan.sh summary`
- `./component-scan.sh legend`
- `./component-scan.sh records`
- `./component-scan.sh manifest`
- `./component-scan.sh catalog`
- `./component-scan.sh validate`

`component-scan.sh` is the canonical inventory source for both the shell legend and `devdash`.

Canonical machine schema:

- `INVENTORY_SCHEMA.md`
- `inventory.schema.json`
- kept as a plain JSON contract, not a JSON Schema-spec document
- `DISCOVERY_RULES.md`
- `operation.schema.json`
- `operation_contract.py`

Discovery rules, terse version:

- walk `~/dev` recursively
- prune excluded directories before descent
- create directory records from `README.md`
- create command records from executable `.sh` and `.zsh` files with metadata
- allow `@taxonomy` to override path-derived lineage
- keep `key` shorthand and `path_key` authoritative

The detailed walk/extraction contract lives in `DISCOVERY_RULES.md`.

## Near-Term Cleanup Queue

1. Remove tracked archive artifacts from git history going forward.
2. Normalize metadata headers across all executable scripts.
3. Consolidate Firefox hardening into one maintained script.
4. Keep README updated when adding features or new top-level groups.
