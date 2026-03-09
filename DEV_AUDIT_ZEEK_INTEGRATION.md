# Dev Audit + Zeek Integration Blueprint

## Purpose
Unify `dev/audit` with Zeek log datamining so investigations can pivot from one connection event (`uid` or `src/dst/port/timestamp`) to a reproducible report bundle:

- terse bullet snapshot
- structured JSON analysis
- integrated markdown narrative
- connection graph (`.dot`, optional `.png`)

## Top-Down Workflow
1. Capture or place Zeek logs in `audit/zlogs/` (fallback `dev/zlogs/`, then `~/zlogs/`).
2. Run `audit.sh` for the full machine snapshot with embedded Zeek section.
3. Run `zeek-audit.sh` for focused network forensics.
4. For targeted drill-down, pass one anchor:
   - `--uid <uid>`
   - or `--src-ip --dst-ip [--dst-port] [--ts]`
5. Review generated artifacts under `audit/report/zeek/`.

## Investigation Model (Operational)
Input:
- `uid` OR tuple (`src_ip`, `dst_ip`, `dst_port`, `timestamp`)
- Zeek log directory

Pipeline:
- Locate anchor connection in `conn.log`
- Build investigation window around anchor time
- Correlate across `dns/ssl/http/quic/files/weird` via uid + endpoint/time
- Extract preceding DNS evidence for destination IP
- Build nearby network context from same source host
- Classify heuristically (`common_port`, `beacon_like_repetition`, `rare_destination`, `long_lived_connection_seen`)
- Output bullets + JSON + markdown + graph

## Directory Structure
```text
dev/
  audit/
    analysis/
      zeek_snapshot.py
    zlogs/
      conn.log
      dns.log
      ssl.log
      http.log
      quic.log
      files.log
      weird.log
    report/
      zeek/
        zeek-<run>.json
        zeek-<run>.summary.txt
        zeek-<run>.md
        zeek-<run>.graph.dot
    audit.sh
    zeek-audit.sh
```

## Commands
Full audit (with Zeek auto-ingest):
```bash
cd ~/dev/audit
./audit.sh
```

Start background capture writing Zeek logs into the configured log dir:
```bash
./zeek-capture.sh start en0
```

Targeted Zeek run by UID:
```bash
./zeek-audit.sh ./zlogs case01 -- --uid CtvOlP1Ej5cQULCyA5
```

Targeted Zeek run by src/dst/port/timestamp:
```bash
./zeek-audit.sh ./zlogs case02 -- \
  --src-ip 192.168.1.157 \
  --dst-ip 75.102.5.99 \
  --dst-port 443 \
  --ts 2026-03-06T20:45:25Z
```

## Shell Sync Requirements
`bootstrap/.zshrc` is the source of truth.

Required command layer:
- fast audit runner
- Zeek capture start/stop/status runner
- Zeek snapshot runner
- UID/tuple drill-down wrappers
- single command to re-publish shell profile to `~/.zshrc`

## Expected Artifacts Per Investigation
- JSON: full machine-readable output for automation
- Markdown: comprehensive narrative for human review
- Summary TXT: terse bullets for quick triage
- DOT/PNG: topology and weight visualization
