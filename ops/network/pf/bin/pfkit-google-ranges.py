#!/usr/bin/env python3
# dev-cmd: alias=pf.google.ranges name="PF Google Ranges" group=net run=user legend=hide desc="Resolve official Google-owned default-domain IPv4 ranges"

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from ipaddress import IPv4Network

GOOG_URL = "https://www.gstatic.com/ipranges/goog.json"
CLOUD_URL = "https://www.gstatic.com/ipranges/cloud.json"


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def ipv4_prefixes(payload: dict) -> list[IPv4Network]:
    prefixes: list[IPv4Network] = []
    for item in payload.get("prefixes", []):
        prefix = item.get("ipv4Prefix")
        if not prefix:
            continue
        prefixes.append(IPv4Network(prefix))
    return prefixes


def subtract_many(base: list[IPv4Network], removals: list[IPv4Network]) -> list[IPv4Network]:
    result = base[:]
    for removal in removals:
        next_result: list[IPv4Network] = []
        for candidate in result:
            if removal.subnet_of(candidate):
                next_result.extend(candidate.address_exclude(removal))
            elif candidate.subnet_of(removal):
                continue
            elif candidate.overlaps(removal):
                print(
                    f"pfkit-google-ranges: unsupported partial overlap: {candidate} vs {removal}",
                    file=sys.stderr,
                )
                return []
            else:
                next_result.append(candidate)
        result = next_result
    return sorted(set(result), key=lambda net: (int(net.network_address), net.prefixlen))


def main() -> int:
    try:
        goog = fetch_json(GOOG_URL)
        cloud = fetch_json(CLOUD_URL)
    except (urllib.error.URLError, TimeoutError) as exc:
        print(f"pfkit-google-ranges: failed to fetch Google IP ranges: {exc}", file=sys.stderr)
        return 1

    goog_prefixes = ipv4_prefixes(goog)
    cloud_prefixes = ipv4_prefixes(cloud)

    google_only = subtract_many(goog_prefixes, cloud_prefixes)
    if not google_only:
        print("pfkit-google-ranges: no Google-owned IPv4 ranges produced", file=sys.stderr)
        return 1

    print(" ".join(str(net) for net in google_only))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
