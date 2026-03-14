<!-- @component: bootstrap -->
<!-- @kind: component -->
<!-- @desc: Install and sync tracked bootstrap files into live system locations -->
<!-- @keywords: bootstrap install sync shell git editor -->

# bootstrap

Environment bootstrap component. Flat layout by design.

## Intent

`bootstrap/` is the install/sync component for tracked machine-level defaults.
Its main job is to keep files in this repo aligned with their live counterparts
under `$HOME`.

## Live Targets

| Tracked file | Live counterpart |
| --- | --- |
| `bootstrap/.zshrc` | `~/.zshrc` |
| `bootstrap/.gitconfig` | `~/.gitconfig` |
| `bootstrap/.editorconfig` | `~/.editorconfig` |

## Entry Points

- `./install.sh`: sync tracked bootstrap files into home targets
- `bi`: shell wrapper for `./install.sh`
- `pz`: link `bootstrap/.zshrc` into `~/.zshrc` and reload
- `pzcp`: copy `bootstrap/.zshrc` into `~/.zshrc` and reload

## Shell Layout

Shell bootstrap logic lives in `bootstrap/shell/` and is split by concern:

- `dev.sh`: top-level loader sourced by `bootstrap/.zshrc`
- `base.sh`: colors, prompt, shell environment, shared helpers
- `inventory.sh`: legend, records, and dashboard wrappers
- `bootstrap.sh`: bootstrap install/sync commands
- `audit.sh`: audit and Zeek shell wrappers
- `system.sh`: nav, git, network, dns, and general shell helpers
- `devtools.sh`: dev-only helpers such as `devzip`, `ed`, and `gorilla`

## Notes

- The shell layer is interactive-only; non-interactive shells stop at the loader.
- The canonical machine inventory source remains `../component-scan.sh`.
- The shell no longer auto-prints the legend on startup by default. Set `DEV_SHELL_SHOW_LEGEND=1` if you want that behavior back for a session.
