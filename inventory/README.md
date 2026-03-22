<!-- dev-component: id=inventory kind=support group=sys desc="Inventory and manifest extraction modules for the dev tree" -->

# inventory

Support package for `component-scan.sh`.

This package owns:

- tree walking
- command discovery
- summary/legend/manifest rendering
- validation

It does not own shell initialization or shell publishing. That belongs to `bootstrap/`.

modules are split by responsibility:

- `shared.py`: constants and common parsing helpers
- `discovery.py`: tree walk and record extraction
- `commands.py`: canonical command-object normalization
- `output.py`: summary, legend, index, shell, and manifest rendering
- `validate.py`: metadata validation rules
- `cli.py`: command entrypoint orchestration
