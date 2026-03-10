# Component Protocol

This repo treats `~/dev` as a recursive component tree.

## Intent

- A directory becomes an explicit component when its `README.md` declares component metadata.
- Runnable scripts become discoverable commands when they declare command metadata.
- `devdash` and other rollups should consume one shared tree-walk output instead of re-implementing discovery.

## README Metadata

Declare component identity near the top of `README.md` with HTML comments:

```md
<!-- @component: audit -->
<!-- @kind: component -->
<!-- @desc: Quick macOS audit and Zeek analysis pipeline -->
<!-- @tags: audit macos zeek -->
```

Fields:

- `@component`: stable component id
- `@kind`: `component` | `subcomponent` | `support`
- `@desc`: one-line summary used in rollups
- `@tags`: space-separated taxonomy tags

Rules:

- `component`: top-level or independently meaningful unit
- `subcomponent`: nested unit with distinct responsibility
- `support`: content directory that should be visible but not treated as a primary control surface

If a `README.md` exists without metadata, discovery may still show the directory as implicit support, but it is not a first-class component.

## Script Metadata

Runnable scripts should declare:

```bash
# @desc: one-line description
# @tags: space-separated taxonomy tags
# @run: user|sudo
```

Optional:

```bash
# @alias: shortname
# @owner: firstparty
```

Rules:

- `@desc` is required for dashboard inclusion.
- `@run` controls invocation mode in dashboards.
- `@alias` is display metadata only; it does not create shell aliases automatically.

## Discovery Contract

The shared scanner walks `~/dev` recursively and emits records for:

- explicit components and subcomponents from `README.md`
- implicit support directories that have a `README.md` but no metadata
- runnable scripts with script metadata

Each script record is attached to the nearest explicit ancestor component; if none exists, it falls back to the top-level directory name.

## Output Shapes

Human summary:

- terse tree-style stdout for quick review
- components first, commands nested beneath their owning component

Machine records:

- tab-separated records for dashboards and generators
- one record type per line: `dir` or `cmd`

This is the source of truth for `devdash` inventory views.
