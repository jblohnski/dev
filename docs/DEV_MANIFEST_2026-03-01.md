# Dev Manifest (Snapshot)

Date: 2026-03-01 01:46:21 PST

## Ask Summary

This repo should become a turn-key, self-defining machine profile system:

1. Clone on a new machine.
2. Run bootstrap/publish to establish terminal + shell identity.
3. Run operational scripts for hardening/interrogation.
4. Run audit to collect and analyze posture data.
5. Keep documentation current as new capabilities are added.

## Design Intent

- Minimal size, maximal function.
- Human-readable structure first.
- Convention-driven metadata for discoverability.
- Patch-first change control.

## Taxonomy (Phase 1)

Top-level intent by lifecycle:

1. `bootstrap/`
   - Dotfiles and profile publication.
   - Terminal/editor/git baseline config.
2. `ops/`
   - Scripts that act on or interrogate the live machine.
   - Example domains: `system`, `network`, `browser`, `diagnostics`.
3. `audit/`
   - Evidence collection, baseline/current compare, reporting.
4. `pfkit/`
   - PF-specific policy tooling; retained as focused subsystem.
5. `arkenfox/`
   - Upstream/vendor material and integration points.
6. `projects/`
   - Independent projects, not part of core machine posture workflow.

## Turn-Key Runbook (Target)

1. `git clone ... ~/dev`
2. `./bootstrap/bin/publish-zshrc.sh`
3. `source ~/.zshrc`
4. `ops` hardening/interrogation commands as needed.
5. `cd audit && ./audit.sh --baseline`
6. `cd audit && ./audit.sh`
7. Review `audit/report/summary.md` and `summary.json`.

## Documentation Rule

When a new feature is added, update one of:

- `README.md` for user-facing behavior
- `docs/` for conventions or architecture

Behavior changes without doc updates are considered incomplete.
