<!-- @component: audit -->
<!-- @kind: component -->
<!-- @desc: Quick macOS audit and Zeek analysis pipeline -->
<!-- @tags: audit macos zeek -->

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
./audit.sh --zeek-dir ./zlogs
./audit.sh --no-zeek
./audit.sh --zeek-ipinfo
```

## Zeek integration

The audit workflow now auto-ingests Zeek logs when available.

- Primary path: `audit/zlogs/`
- Fallback path: `../zlogs/`
- Local direct-log fallback: `audit/*.log`
- Home path: `~/zlogs/`
- Env override: `ZEEK_LOG_DIR=/absolute/path`
- Required file: `conn.log`
- Optional files: `dns.log`, `ssl.log`, `http.log`, `quic.log`, `files.log`, `weird.log`

Background capture quickstart (replace `en0` if needed):

```bash
./zeek-capture.sh start en0
```

That wrapper starts Zeek with the project’s expected write-path parameters:

```bash
sudo zeek -i en0 -C "Log::default_logdir=$HOME/zlogs"
```

- `-i en0`: capture from the selected interface
- `-C`: ignore checksum validation issues common with NIC offload
- `Log::default_logdir=...`: write `conn.log`, `dns.log`, and related files into the configured log directory

Useful variants:

```bash
./zeek-capture.sh status
./zeek-capture.sh stop
ZEEK_LOG_DIR=./zlogs ./zeek-capture.sh start en0
./zeek-capture.sh start en0 -- Site::local_nets+=192.168.1.0/24
./zeek-logsync.sh
```

Standalone Zeek report command:

```bash
./zeek-audit.sh
./zeek-audit.sh ./zlogs run01
./zeek-audit.sh ./zlogs run01 -- --uid CtvOlP1Ej5cQULCyA5
./zeek-audit.sh ./zlogs run02 -- --src-ip 192.168.1.157 --dst-ip 75.102.5.99 --dst-port 443 --ts 2026-03-06T20:45:25Z
```

Artifacts are written under `audit/report/`:

- `zeek/zeek-<id>.json`
- `zeek/zeek-<id>.summary.txt`
- `zeek/zeek-<id>.md`
- `zeek/zeek-<id>.graph.dot` (and PNG if Graphviz `dot` exists)

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
- `zeek` (present when Zeek logs are found and parsed)

Notes:

- JSON shape is intentionally flexible and may evolve.
- Delta source file is `state/net-last.json` (auto-written, git-ignored).
- This tool is for quick assessment, not deep forensic capture.
