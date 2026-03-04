# audit — quick macOS snapshot

This is a lightweight, glanceable audit for macOS with a network/process-first view.

## What it does

- Runs a fast local assessment
- Writes exactly one JSON snapshot
- Prints a short color summary in stdout
- Highlights essential anomalies only
- Tracks lightweight network delta between runs

## Usage

```bash
./audit.sh
```

Optional:

```bash
./audit.sh --out /tmp/my_snapshot.json
./audit.sh --id maple
./audit.sh --no-color
```

## JSON output

Default path:

- `audit-<word>.json`

Top-level sections:

- `cat` (`audit`)
- `id` (short run word)
- `ts` (timestamp UTC)
- `host`
- `sys` (system snapshot)
- `sec` (security flags)
- `net` (default iface/gateway, interfaces, DNS, DHCP, connections, delta)
- `proc` (top network-active processes + top CPU processes)
- `dsk` (disk snapshot)
- `per` (persistence counts)
- `findings` (anomaly list)

Notes:

- JSON shape is intentionally flexible and may evolve.
- Delta source file is `state/net-last.json` (auto-written, git-ignored).
- This tool is for quick assessment, not deep forensic capture.
