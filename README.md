<!-- @component: dev -->
<!-- @kind: component -->
<!-- @desc: Personal machine automation and diagnostics workspace -->
<!-- @tags: workspace automation diagnostics -->

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
4. `pfkit/`:
   PF-specific firewall toolkit (kept separate due to privileged/network policy scope).
5. `arkenfox/`:
   Upstream/vendor material and related support scripts.
6. `projects/`:
   Independent project sandboxes, excluded from this repo workflow.

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

Runnable scripts should include:

```bash
# @desc: one-line description
# @tags: space-separated taxonomy tags
# @run: user|sudo
```

Directory components can declare explicit metadata in `README.md` comment headers. See [COMPONENT_PROTOCOL.md](COMPONENT_PROTOCOL.md).

Shared inventory entrypoint:

- `./component-scan.sh summary`
- `./component-scan.sh records`

## Near-Term Cleanup Queue

1. Remove tracked archive artifacts from git history going forward.
2. Normalize metadata headers across all executable scripts.
3. Consolidate Firefox hardening into one maintained script.
4. Keep README updated when adding features or new top-level groups.
