# Patch Workflow

This repo uses proposal patches by default before applying changes.

## Proposal File Naming

Pattern:

`proposals/<NNN>-<scope>-<intent>-<YYYY-MM-DD>.patch`

Examples:

- `proposals/001-taxonomy-phase1.patch`
- `proposals/002-manifest-taxonomy-conventions-2026-03-01.patch`

## Review Procedure

```bash
git apply --stat proposals/<file>.patch
git apply --check proposals/<file>.patch
less proposals/<file>.patch
```

## Apply Procedure

```bash
git apply proposals/<file>.patch
```

## Reject / Roll Back (if just applied and uncommitted)

```bash
git diff
git restore .
```

Use targeted restore if needed:

```bash
git restore path/to/file
```

## Commit Convention (Optional)

Suggested message style:

`<area>: <intent>`

Examples:

- `taxonomy: introduce bootstrap/ops split`
- `docs: add metadata conventions`
- `shell: add zshrc publish workflow`
