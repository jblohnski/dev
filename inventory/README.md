<!-- @component: inventory -->
<!-- @kind: support -->
<!-- @desc: Inventory and manifest extraction modules for the dev tree -->
<!-- @keywords: inventory manifest discovery support -->

# inventory

support package for `component-scan.sh`.

modules are split by responsibility:

- `shared.py`: constants and common parsing helpers
- `discovery.py`: tree walk and record extraction
- `output.py`: summary, records, legend, index, and manifest rendering
- `validate.py`: metadata validation rules
- `cli.py`: command entrypoint orchestration
