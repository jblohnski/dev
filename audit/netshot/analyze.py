#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path


def load_json_log(path: Path) -> list[dict]:
    if not path.exists():
        return []

    records: list[dict] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return records


def print_counter(title: str, counter: Counter[str], empty_message: str) -> None:
    print(title)
    if not counter:
        print(f"  {empty_message}")
        print()
        return

    for value, count in counter.most_common(5):
        print(f"  {value}: {count}")
    print()


def summarize(zeek_dir: Path) -> int:
    conn_log = zeek_dir / "conn.log"
    ssl_log = zeek_dir / "ssl.log"

    conn_records = load_json_log(conn_log)
    ssl_records = load_json_log(ssl_log)

    top_talkers = Counter()
    top_destinations = Counter()
    tls_servers = Counter()

    for record in conn_records:
        src = record.get("id.orig_h")
        dst = record.get("id.resp_h")
        if src and src != "-":
            top_talkers[src] += 1
        if dst and dst != "-":
            top_destinations[dst] += 1

    for record in ssl_records:
        server_name = record.get("server_name")
        dst = record.get("id.resp_h")
        key = server_name or dst
        if key and key != "-":
            tls_servers[key] += 1

    print_counter("Top talkers", top_talkers, "No connection records found.")
    print_counter("Top destinations", top_destinations, "No connection records found.")
    print_counter("TLS servers observed", tls_servers, "No TLS servers observed.")

    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: analyze.py <zeek-log-directory>", file=sys.stderr)
        return 1

    zeek_dir = Path(argv[1]).expanduser().resolve()
    if not zeek_dir.exists():
        print(f"Zeek log directory does not exist: {zeek_dir}", file=sys.stderr)
        return 1

    return summarize(zeek_dir)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
