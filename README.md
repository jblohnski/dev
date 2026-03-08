# dev

Personal machine automation and diagnostics repo for `~/dev`.

## Taxonomy (phase 1)

Top-level groups are intentionally separated by lifecycle:

1. `bootstrap/`:
   Files used to initialize or publish local environment/profile state.
   Example: shell profile, terminal profiles, dotfile publish scripts.
2. `ops/`:
   Operational scripts that interrogate, harden, or manipulate live system state.
   Example: router checks, macOS hardening, Firefox hardening.
3. `audit/`:
   Analysis pipeline that captures snapshots, compares baseline vs current, and reports findings.
4. `pfkit/`:
   PF-specific firewall toolkit (kept separate due to privileged/network policy scope).
5. `arkenfox/`:
   Upstream/vendor material and related support scripts.
6. `projects/`:
   Independent project sandboxes, excluded from this repo workflow.

## Shell Profile Source of Truth

Canonical tracked shell profile path:

- `bootstrap/zsh/.zshrc`

Publish workflow:

```bash
./bootstrap/bin/publish-zshrc.sh
```

This validates syntax and copies tracked profile to `~/.zshrc` with backup.

## Ops vs Audit

- `ops/`: direct actions and runtime interrogation.
- `audit/`: evidence collection + normalization + reporting.

Rule: keep scripts that *act* in `ops/`; keep scripts that *measure/compare* in `audit/`.

## Zeek Integration

See [DEV_AUDIT_ZEEK_INTEGRATION.md](DEV_AUDIT_ZEEK_INTEGRATION.md) for the integrated Zeek datamining workflow, anchor-based investigation model (`uid` or `src/dst/port/timestamp`), and artifact structure.

## Metadata Convention (for legend/dashboard)

Runnable scripts should include:

```bash
# @desc: one-line description
# @tags: space-separated taxonomy tags
# @run: user|sudo
```

## Near-Term Cleanup Queue

1. Remove tracked archive artifacts from git history going forward.
2. Normalize metadata headers across all executable scripts.
3. Consolidate Firefox hardening into one maintained script.
4. Keep README updated when adding features or new top-level groups.
