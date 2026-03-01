# Script Metadata Conventions

All runnable scripts should include a standard header directly under shebang:

```bash
#!/usr/bin/env bash
# @desc: One-line imperative summary
# @tags: space-separated tags
# @run: user|sudo
```

## Required Fields

1. `@desc`
   - 5-12 words.
   - Describes what command does, not implementation detail.
2. `@tags`
   - Controlled vocabulary where possible.
3. `@run`
   - `user` for non-privileged.
   - `sudo` when root/privileged actions are required.

## Suggested Tag Vocabulary

- Lifecycle: `bootstrap`, `ops`, `audit`
- Domain: `system`, `network`, `dns`, `browser`, `firewall`, `logs`, `diag`
- Platform: `macos`, `linux`
- Risk: `safe`, `mutating`, `privileged`

Example:

```bash
# @tags: ops network dns macos safe
```

## Naming Conventions

- File names: kebab-case (`firefox-harden.sh`).
- Functions: snake_case (`publish_zshrc`).
- Avoid vague names (`tool.sh`, `script.sh`, `tmp.sh`).

## Comment Conventions

- Use comments for intent and safety boundaries.
- Avoid comments that restate obvious syntax.
- Add one-line usage when behavior is non-obvious.

## Definition of Done (Scripts)

1. Metadata header present.
2. `set -euo pipefail` for bash scripts.
3. Basic input validation for external side effects.
4. Output messages indicate success/failure clearly.
