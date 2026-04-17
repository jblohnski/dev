<!-- dev-component: id=bootstrap kind=component group=sys desc="Install and sync tracked bootstrap files into live system locations" -->

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

- `bootstrap.install`: discovered public command for `./install.sh`
- `pz`: link `bootstrap/.zshrc` into `~/.zshrc` and reload
- `pzcp`: copy `bootstrap/.zshrc` into `~/.zshrc` and reload

## Shell Layout

Shell bootstrap logic lives in `bootstrap/shell/` and is split by concern:

- `dev.sh`: top-level loader sourced by `bootstrap/.zshrc`
- `base.sh`: colors, prompt, shell environment, shared helpers
- `inventory.sh`: summary, legend, validate, manifest, dashboard wrappers, and discovered script alias publication
- `bootstrap.sh`: bootstrap install/sync commands
- `audit.sh`: audit and Zeek shell wrappers
- `system.sh`: nav, git, network, dns, and general shell helpers
- `devtools.sh`: dev-only helpers such as `devzip`, `ed`, and `gorilla`

## Notes

- The shell layer is interactive-only; non-interactive shells stop at the loader.
- `bootstrap/` is about initialization, publishing, and shell/runtime setup.
- Command discovery and legend generation are not defined here; they are delegated to `../component-scan.sh` and the `inventory/` package.
- Script-backed component commands are published into the interactive shell from inventory scan output during init.
- The shell no longer auto-prints the legend on startup by default. Set `DEV_SHELL_SHOW_LEGEND=1` if you want that behavior back for a session.
