<!-- @component: bootstrap -->
<!-- @kind: component -->
<!-- @desc: Environment bootstrap and shell profile source of truth -->
<!-- @tags: bootstrap shell profile -->

# bootstrap

Environment bootstrap component. Flat layout by design.

- `.zshrc`: tiny tracked loader sourced by `~/.zshrc`
- `shell/dev.sh`: tracked shell functions, aliases, and legend logic
- `shell/inventory.sh`: shell wrappers around the canonical `component-scan.sh` inventory
- `terminal/`: terminal profile artifacts
- `git/`: git defaults/templates
- `editor/`: editor defaults (`.editorconfig`)
