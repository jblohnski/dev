# Component Protocol

This repo treats `~/dev` as a recursive component tree.

## Intent

- A directory becomes an explicit component when its `README.md` declares component metadata.
- Runnable scripts become discoverable commands when they declare command metadata.
- Shell legend commands and `devdash` should consume one shared inventory stream instead of re-implementing discovery.

## Canonical Taxonomy

Inventory should adhere to one canonical hierarchy:

1. `component`
2. `group`
3. `command`

Canonical record fields:

- `type`: `dir` | `cmd`
- `source`: `readme` | `script` | `shell`
- `path`: repo-relative path to the source file or directory
- `component`: owning component id
- `group`: display subgroup inside the owning component
- `name`: command name when `type=cmd`
- `run`: `user` | `sudo` when `type=cmd`
- `tags`: taxonomy tags
- `alias`: preferred display alias when present
- `desc`: one-line summary

Interpretation rules:

- `component` is the stable owner used for merged output.
- `group` is the human-facing subgroup used by `l` and `devdash`.
- `path` is always preserved in machine output and richer dashboards, even when terse legends omit it.

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
- Every tracked directory with a `README.md` should eventually declare explicit metadata.

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
- Executable scripts in tracked components are expected to declare all core metadata fields.

## Shell Metadata

Shell command wrappers remain valid inventory, but they should be thin wrappers around file-backed functionality whenever possible.

Rules:

- Shell legend commands are discovered from `bootstrap/shell/*.sh`.
- `## section` headers define shell groups.
- `# name: description` comment lines define legend metadata for the next alias or function of the same name.
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

## Discovery Contract

The shared scanner walks `~/dev` recursively and emits records for:

- explicit components and subcomponents from `README.md`
- implicit support directories that have a `README.md` but no metadata
- runnable scripts with script metadata
- shell aliases/functions discovered from `bootstrap/shell/*.sh`

Each script record is attached to the nearest explicit ancestor component; if none exists, it falls back to the top-level directory name.

## Output Shapes

Human summary:

- terse tree-style stdout for quick review
- components first, groups second, commands third

Machine records:

- tab-separated records for dashboards and generators
- one record type per line: `dir` or `cmd`

Validation:

- `./component-scan.sh validate`
- flags missing metadata, invalid kinds, invalid run modes, duplicate component ids, and non-canonical shell sections

This is the source of truth for `devdash`, `l`, and related inventory views.
