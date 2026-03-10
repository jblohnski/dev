# Component Sweep

## Goal
Reduce coupling between top-level components (`bootstrap`, `audit`, `ops`) and make behavior inferable from tree + metadata.

## Component Contract
- Each top-level component has exactly one `README.md`.
- Components expose stable entrypoints (scripts/functions) with metadata tags.
- Prefer env vars over hardcoded absolute paths.
- Generated/runtime data stays out of tracked source.

## Current Couplings (Top-Down)
1. `bootstrap -> home shell`
- Coupling: writes `~/.zshrc` (expected boundary).
- Status: simplified to `pz` function in `bootstrap/.zshrc`.

2. `audit -> zlogs location`
- Coupling: requires `conn.log` at known path.
- Status: supports `--zeek-dir`, `ZEEK_LOG_DIR`, `audit/zlogs`, `../zlogs`, `~/zlogs`.

3. `zdash -> absolute user path`
- Coupling: had hardcoded `/Users/jagov/dev/zlogs`.
- Status: replaced with `ZEEK_LOG_DIR` / `~/zlogs` fallback.

4. `dev root -> excluded directories`
- Coupling: `projects/` and `proposals/` are ignored by design.
- Status: local READMEs can exist but are intentionally non-versioned.

## Sweep Plan
1. Entrypoint normalization
- Ensure every runnable script has `@desc/@tags/@run`.
- Keep shell aliases/functions as thin wrappers around component entrypoints.

2. Path normalization
- Remove remaining absolute paths.
- Standardize env vars: `AUDIT_DIR`, `ZEEK_LOG_DIR`, `DEV_BOOTSTRAP_DIR`.

3. Readme aggregation model
- Add a lightweight tree-walk script that discovers component READMEs and prints a rollup index.
- Use metadata tags as the legend source for dashboards.
- Status: `component-scan.sh` is the shared inventory source for `devdash`.

4. Data boundary enforcement
- Re-check ignores for runtime artifacts (`zlogs`, `audit/report`, `audit/state`, captures).
- Keep only source/config/docs in commits.

5. Dashboard alignment
- Keep `devdash` as control surface.
- Add a “component index” view generated from READMEs + metadata scan.
- Status: `component-scan.sh` now feeds both `devdash` and the shell legend.
