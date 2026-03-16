# discovery rules

terse contract for walking `~/dev` and extracting the manifest.

## principle

Each part does one job:

- walk the tree
- extract metadata
- classify records
- emit manifest

core executable abstraction:

- an `operation` is the broad leaf type
- `command`, `function`, `script`, and `binary` are operation variants

Do not mix naming policy, UI policy, and crawl policy unless required for discovery.

## walk rules

- Root is `~/dev` unless another root is passed explicitly.
- Walk recursively.
- Prune excluded directories before descending.
- Current excluded directories are defined in `component-scan.sh`.
- A directory is discoverable when it remains in the walk.
- A directory becomes a first-class directory record only when a `README.md` is present.

## directory rules

- `README.md` metadata defines explicit component identity.
- Missing metadata still allows an implicit support directory record.
- Directory names do not define semantic taxonomy by themselves.
- `@taxonomy` may define semantic lineage explicitly.

## script rules

- Shell scripts are considered for discovery when they are executable and end in `.sh` or `.zsh`.
- Scripts without `@desc` are skipped from manifest command records.
- Script filename does not need to match taxonomy.
- `@taxonomy` may be declared in the script header.
- Without explicit taxonomy, lineage is derived from owning component, group, and command token.

## shell wrapper rules

- `bootstrap/shell/*.sh` is a separate discovery source.
- Shell wrappers are inventory records, not the source of component identity.
- Prefer thin wrappers over embedding primary behavior in shell aliases.

## manifest rules

- `manifest` is the canonical machine output.
- `key` is shorthand and may collide.
- `path_key` is the stable unique identity.
- `top_level` is the first taxonomy constraint and is either `shell` or `dev`.
- `taxonomy_key` is the explicit logical lineage.
- `index` holds aggregate walk counts and skip counts.
- legend/index commands are projections of valid operations.

## operation rules

- `operation` is the generic executable object.
- It is bound to path identity and logical taxonomy at the same time.
- Path identity and logical taxonomy must remain separate.
- Operation type is broad; taxonomy is conceptual.
- `shell` is the top-level category for shell-loaded aliases, wrappers, and shell-native operations.
- `dev` is the top-level category for the discovered `dev/` corpus.
- if a discovered executable record does not produce a valid `op`, it is not a legit command/index entry.
- a command is the alias or pointer view of a valid operation.
- keywords are secondary facets used to re-sort and refilter operations.

## modularity rules

- Discovery should stay composable.
- One module should walk.
- One module should normalize records.
- One module should render outputs.
- New outputs should consume the same normalized record set.

This is the intended shape: small parts, clean joins, Unix-style assembly.
