# inventory schema

canonical machine catalog for `~/dev` discovery.

primary emitter:

```bash
python3 ./component-scan.sh manifest
```

schema file:

- `inventory.schema.json`

## design

The catalog separates three identities that were previously blurred together:

- `key`: short taxonomic handle such as `n.s`
- `path_key`: canonical unique structural key derived from path and command token
- `taxonomy_key`: verbose semantic lineage such as `ops/network/router`

That split is intentional:

- `key` is for quick human reference and shorthand grouping.
- `path_key` is the collision-proof identity for storage, joins, and updates.
- `taxonomy_key` is the explicit semantic lineage for dashboards and reasoning.

## payload

Top-level object:

- `schema_version`
- `generated_at`
- `root`
- `index`
- `items`

`inventory.schema.json` is intentionally plain JSON, not a JSON Schema-spec document.

It is a lightweight contract file that names the object shape without bringing in validator-specific syntax.

Each item is one discovered node:

- `record_type`: `dir` or `cmd`
- `entity_type`: `component`, `subcomponent`, `support`, or `command`
- `source`: `readme`, `script`, or `shell`
- `component_id`: owning component id
- `parent_component_id`: parent component id when applicable
- `parent_key`: parent node identity using `path_key`
- `group`: command group, otherwise `null`
- `name`: human label
- `cmd`: command token for command records, otherwise `null`
- `run`: `user` or `sudo` for command records, otherwise `null`
- `desc`: one-line summary
- `keywords`: normalized keyword array
- `alias`: alias when present, otherwise `null`
- `path`: repo-relative source path
- `docs_path`: nearest README path
- `declared_taxonomy`: raw taxonomy declared in metadata when present
- `taxonomy_source`: `explicit` or `derived`
- `taxonomy_path`: ordered semantic lineage segments

the `index` object holds aggregate walk data:

- `eligible_dirs`: repo-relative directories included in the walk
- `skipped_dirs`: pruned directories
- `counts`: aggregate emitted and discovered totals
- `skipped`: aggregate skip reasons

legend and command index outputs are downstream views over valid operation objects, not independent discovery products.

## key rules

`key` is not guaranteed unique.

That is by design. A short key like `n.s` should stay short and semantically readable. Use `path_key` whenever you need a stable unique identity.

## taxonomy declaration

Taxonomy does not need to match the script filename.

Optional metadata:

```md
<!-- @taxonomy: net/scan -->
```

```bash
# @taxonomy: net/scan
```

Rules:

- If `@taxonomy` is declared on the record, it is used directly.
- If a command omits `@taxonomy`, the scanner derives taxonomy from the owning component plus group and command token.
- A script is not required to encode taxonomy in its filename.
- Prefer declaring shared lineage in a component `README.md` when you do not want to burden each script with it.

Examples:

```json
{
  "key": "w.w",
  "path_key": "cmd:wifiscan/wifiscan.sh#wifiscan",
  "declared_taxonomy": null,
  "taxonomy_source": "derived",
  "taxonomy_key": "wifiscan/wifi/wifiscan"
}
```

```json
{
  "key": "n.s",
  "path_key": "cmd:ops/network/router.sh#router",
  "declared_taxonomy": "net/scan",
  "taxonomy_source": "explicit",
  "taxonomy_key": "net/scan"
}
```
