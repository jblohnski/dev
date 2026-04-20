#!/usr/bin/env python3
# dev-cmd: alias=pfkit.resolve-hosts name="pfkit resolve hosts" group=net run=user legend=hide desc="Resolve configured HTTPS allowlist hostnames into IPv4 /32 CIDRs for pfkit state"
from __future__ import annotations

import argparse
import json
import socket
import sys
from ipaddress import IPv4Network
from pathlib import Path


def resolve_host(host: str) -> list[str]:
    return sorted(
        {
            item[4][0]
            for item in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
            if ":" not in item[4][0]
        }
    )


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--state-dir")
    parser.add_argument("--state-name", default="extra-https-hosts.json")
    parser.add_argument("hosts", nargs="*")
    args = parser.parse_args()

    ranges: list[str] = []
    resolved: dict[str, list[str]] = {}
    failures: dict[str, str] = {}

    for host in args.hosts:
        try:
            addrs = resolve_host(host)
            if not addrs:
                failures[host] = "no IPv4 results"
                continue
            resolved[host] = addrs
            ranges.extend(str(IPv4Network(f"{addr}/32", strict=False)) for addr in addrs)
        except socket.gaierror as exc:
            failures[host] = str(exc)

    deduped = sorted(set(ranges), key=lambda x: tuple(int(part) for part in x.split("/")[0].split(".")))

    if args.state_dir:
        state_dir = Path(args.state_dir)
        state_dir.mkdir(parents=True, exist_ok=True)
        payload = {
            "hosts": args.hosts,
            "resolved": resolved,
            "failures": failures,
            "range_count": len(deduped),
            "ranges": deduped,
        }
        (state_dir / args.state_name).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    if deduped:
        print(" ".join(deduped))
        return 0

    if failures:
        for host, reason in failures.items():
            print(f"pfkit-resolve-hosts: {host}: {reason}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
