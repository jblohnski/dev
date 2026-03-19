# discovery rules

Terse contract for walking `~/dev` and extracting shared inventory.

Primary source of truth:

- `COMPONENT_PROTOCOL.md`

## walk

- root is `~/dev` unless overridden
- walk recursively
- prune excluded directories before descent
- emit directory records only from directories with `README.md`

## directories

- `README.md` metadata defines explicit identity
- `component` and `subcomponent` directories may own commands
- `support` directories stay documented but do not own the primary command surface

## scripts

- consider executable `.sh` and `.zsh` files
- skip script command records when `@desc` is missing
- use structure-first grouping when the script lives in a real child directory under its owner
- otherwise fall back to keyword-derived grouping

## shell wrappers

- discover from `bootstrap/shell/*.sh`
- use canonical shell sections
- keep shell wrappers thin

## outputs

- `summary` and `legend` are human views
- `index` is the shared command-reference list
- `manifest` and `catalog` are machine inventory payloads
- only valid command objects should survive into command-facing downstream views
