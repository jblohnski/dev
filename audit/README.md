# maudit — minimal macOS audit toolkit

`maudit` captures a snapshot of high-signal macOS system state, compares it against a baseline, and generates a compact executive summary plus both normalized and raw diffs.

## Quick start

Create/refresh a baseline:

```bash
./audit.sh --baseline
```

Run an audit (current snapshot + analysis + baseline comparison):

```bash
./audit.sh
```

Optional: show collector output during the run:

```bash
./audit.sh --verbose
```

Reset all generated state (baseline/current/report/archives):

```bash
./audit.sh --reset
```

## Outputs

After `./audit.sh`, results are written to:

- `current/` — latest snapshot
- `report/`:
  - `summary.md` — human-readable executive summary + key metrics
  - `summary.json` — machine-readable metrics + diff stats
  - `diff_normalized.txt` — baseline vs current diff with volatile lines normalized out
  - `diff_raw.txt` — raw `diff -ru` output (noisy, forensic reference)
  - `collectors/` — per-collector stdout/stderr logs for the run

## Non-clobbering behavior

Before writing new data, `maudit` archives any existing `baseline/`, `current/`, and `report/` directories into:

- `archives/baseline_<timestamp>/`
- `archives/current_<timestamp>/`
- `archives/report_<timestamp>/`

Snapshots are built in temporary directories and then swapped into place (atomic move), so partially-written runs are avoided.

## Structure

- `collectors/` — individual data collectors (shell scripts)
- `scripts/analyze_run.py` — normalization + metrics extraction + executive summary generation
- `baseline/` — trusted reference snapshot
- `current/` — latest snapshot
- `report/` — summary + diffs
- `archives/` — previous snapshots/reports (auto-created)

## Notes

- Baseline should be created on a known-clean system state.
- The “risk level” in `summary.md` is a simple heuristic for triage; use the raw artifacts for deeper validation.


```sh
# compress excluding .git/ and similar project meta-data files
alias zipa='zip -r audit.zip audit \
  -x "audit/.git/*" \
  -x "audit/archives/*" \
  -x "audit/__pycache__/*" \
  -x "audit/*/__pycache__/*" \
  -x "audit/*.pyc" \
  -x "audit/*.pyo" \
  -x "audit/baseline/*" \
  -x "audit/current/*" \
  -x "audit/report/*" \
  -x "audit/state/*" \
  -x "audit/*.log" \
  -x "audit/*.pcap*" \
  -x "audit/.DS_Store" \
  -x "audit/*/.DS_Store" \
  -x "audit/._*"'

```

```sh

# create project ython venv
builtin cd ~/dev/audit
python3 -m venv .venv
source .venv/bin/activate
pip install jinja2

```
