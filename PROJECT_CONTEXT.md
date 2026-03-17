# Dev Project Context

This repository contains independent tooling modules used for system auditing,
network analysis, and operational diagnostics.

Design goals:
- modular tools
- minimal dependencies
- simple CLI execution
- readable outputs
- no coupling between modules

Directory structure:

dev/
  audit/
  apps/
  bootstrap/
  ops/

Modules must be independent unless explicitly stated.

---

## netshot module

Purpose:
Quick network telemetry snapshot.

Pipeline:

tcpdump
   ↓
pcap
   ↓
zeek analysis
   ↓
python summarizer
   ↓
console report

Expected output format:

Top talkers
-----------
IP → connection count

Top destinations
----------------
IP service

TLS servers observed
--------------------
hostname

Behavior:

- capture duration configurable
- default capture: 40 seconds
- requires sudo for packet capture
- output stored in module output directory

---

## Tooling environment

Primary tools installed via Homebrew:

zeek
tcpdump
nmap
lnav
jq
ripgrep
python@3.12
simdjson
unbound

These tools should be used when relevant rather than re-implementing
functionality.

Example:

Use Zeek logs instead of parsing PCAP manually.

---

## Coding conventions

Shell scripts:

- POSIX compatible where possible
- minimal dependencies
- clear CLI arguments
- informative output

Python:

- Python 3.12+
- avoid heavy libraries
- focus on performance and readability
- prefer built-in modules

---

## Development philosophy

Tools should:

1. work standalone
2. produce useful summaries quickly
3. expose deeper data for manual inspection
4. avoid unnecessary abstraction

Example workflow:

capture → analyze → summarize → investigate

---

## Future enhancements

Possible additions:

- network connection graph
- ASN / GeoIP enrichment
- anomaly detection
- periodic automated captures
