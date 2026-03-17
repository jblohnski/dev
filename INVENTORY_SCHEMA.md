# inventory schema

Canonical machine catalog for `~/dev` discovery.

Primary emitter:

```bash
python3 ./component-scan.sh manifest
```

Schema file:

- `inventory.schema.json`

## payload

Top-level object:

- `schema_version`
- `generated_at`
- `root`
- `index`
- `items`

Each item is one discovered node:

- `record_type`: `dir` or `cmd`
- `entity_type`: `component`, `subcomponent`, `support`, or `command`
- `source`: `readme`, `script`, or `shell`
- `top_level`: `shell` or `dev`
- `component_id`: owning component id
- `parent_component_id`: parent component id when applicable
- `parent_key`: parent node identity using `path_key`
- `group`: command group, otherwise `null`
- `name`: human label
- `cmd`: preferred command token for command records
- `run`: `user` or `sudo` for command records, otherwise `null`
- `desc`: one-line summary
- `keywords`: normalized keyword array
- `alias`: alternate or display invocation token when present
- `path`: repo-relative source path
- `docs_path`: nearest README path
- `declared_taxonomy`: raw taxonomy declared in metadata when present
- `taxonomy_source`: `explicit` or `derived`
- `taxonomy_key`: resolved logical lineage
- `taxonomy_path`: ordered taxonomy segments

The `index` object holds aggregate walk data:

- `eligible_dirs`
- `skipped_dirs`
- `counts`
- `skipped`

## identity rules

- `key` is shorthand and may collide
- `path_key` is the authoritative structural identity
- `taxonomy_key` is the resolved logical lineage

Keep path identity and logical taxonomy separate.

## downstream views

- `legend` is a terse human projection
- `index` is the shared command-reference list used by richer consumers such as `devdash`
- display views may choose one canonical alias while still preserving `path`, `alias`, `name`, and `desc` in machine-readable outputs

## example

```json
{
  "key": "d.a.n",
  "path_key": "cmd:apps/netshot/netshot.sh#netshot",
  "top_level": "dev",
  "component_id": "apps",
  "group": "netshot",
  "name": "Netshot",
  "cmd": "netshot",
  "alias": null,
  "desc": "Capture a short packet trace, run Zeek, and summarize the result",
  "taxonomy_source": "derived",
  "taxonomy_key": "dev/apps/netshot/netshot"
}
```
