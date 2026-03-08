#!/usr/bin/env python3
"""Zeek log snapshot + correlation + graph export for local audit workflows."""

from __future__ import annotations

import argparse
import ipaddress
import json
import socket
import subprocess
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from statistics import mean, pstdev
from typing import Any


@dataclass
class Anchor:
    uid: str
    ts: float
    src_ip: str
    dst_ip: str
    dst_port: int | None


def to_float(v: Any) -> float | None:
    try:
        if v in (None, "", "-"):
            return None
        return float(v)
    except Exception:
        return None


def to_int(v: Any) -> int | None:
    try:
        if v in (None, "", "-"):
            return None
        return int(float(v))
    except Exception:
        return None


def ts_iso(ts: float | None) -> str | None:
    if ts is None:
        return None
    return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def parse_ts_value(value: str | None) -> float | None:
    if not value:
        return None
    value = value.strip()
    try:
        return float(value)
    except Exception:
        pass

    # Accept ISO-like inputs, including trailing Z.
    v = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(v).timestamp()
    except Exception:
        return None


def parse_zeek_tsv(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []

    fields: list[str] = []
    rows: list[dict[str, Any]] = []

    with path.open("r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line:
                continue
            if line.startswith("#fields"):
                fields = line.split("\t")[1:]
                continue
            if line.startswith("#"):
                continue
            if not fields:
                continue

            parts = line.split("\t")
            if len(parts) < len(fields):
                parts.extend([""] * (len(fields) - len(parts)))
            rec = dict(zip(fields, parts))

            rec["ts"] = to_float(rec.get("ts"))
            rec["id.orig_p"] = to_int(rec.get("id.orig_p"))
            rec["id.resp_p"] = to_int(rec.get("id.resp_p"))
            rec["duration"] = to_float(rec.get("duration"))
            rec["orig_bytes"] = to_int(rec.get("orig_bytes"))
            rec["resp_bytes"] = to_int(rec.get("resp_bytes"))
            rows.append(rec)
    return rows


def safe_private_ip(ip: str) -> bool:
    try:
        return ipaddress.ip_address(ip).is_private
    except Exception:
        return False


def reverse_dns(ip: str) -> str | None:
    try:
        return socket.gethostbyaddr(ip)[0]
    except Exception:
        return None


def ipinfo(ip: str) -> dict[str, Any]:
    try:
        out = subprocess.check_output(["curl", "-s", f"https://ipinfo.io/{ip}/json"], text=True, timeout=4)
        obj = json.loads(out)
    except Exception:
        return {}

    asn = None
    org = obj.get("org")
    if isinstance(org, str) and org.startswith("AS"):
        parts = org.split(" ", 1)
        asn = parts[0]
        org = parts[1] if len(parts) > 1 else org

    return {
        "asn": asn,
        "org": org,
        "country": obj.get("country"),
        "region": obj.get("region"),
    }


def top_counter(values: list[Any], n: int) -> list[dict[str, Any]]:
    cnt = Counter(v for v in values if v not in (None, "", "-"))
    return [{"value": k, "count": v} for k, v in cnt.most_common(n)]


def detect_beacons(conn: list[dict[str, Any]], min_hits: int = 6) -> list[dict[str, Any]]:
    buckets: defaultdict[tuple[str, str, int | None], list[float]] = defaultdict(list)
    for r in conn:
        ts = r.get("ts")
        if ts is None:
            continue
        key = (r.get("id.orig_h", ""), r.get("id.resp_h", ""), r.get("id.resp_p"))
        buckets[key].append(ts)

    suspects: list[dict[str, Any]] = []
    for key, times in buckets.items():
        if len(times) < min_hits:
            continue
        times.sort()
        intervals = [times[i + 1] - times[i] for i in range(len(times) - 1)]
        if not intervals:
            continue

        avg = mean(intervals)
        sd = pstdev(intervals) if len(intervals) > 1 else 0.0
        cv = 0.0 if avg == 0 else sd / avg

        if 5 <= avg <= 3600 and cv <= 0.2:
            suspects.append(
                {
                    "src": key[0],
                    "dst": key[1],
                    "dst_port": key[2],
                    "hits": len(times),
                    "avg_interval_s": round(avg, 2),
                    "jitter_cv": round(cv, 3),
                }
            )

    suspects.sort(key=lambda x: (x["hits"], -x["avg_interval_s"]), reverse=True)
    return suspects[:20]


def find_anchor(
    conn: list[dict[str, Any]],
    target_uid: str | None,
    target_ip: str | None,
    src_ip: str | None,
    dst_ip: str | None,
    dst_port: int | None,
    target_ts: float | None,
    tolerance_s: int,
) -> Anchor | None:
    if target_uid:
        for r in conn:
            if r.get("uid") == target_uid:
                return Anchor(
                    uid=r.get("uid", ""),
                    ts=r.get("ts") or 0.0,
                    src_ip=r.get("id.orig_h", ""),
                    dst_ip=r.get("id.resp_h", ""),
                    dst_port=r.get("id.resp_p"),
                )

    # Tuple mode: src + dst required, plus optional dst_port + ts proximity.
    if src_ip and dst_ip:
        candidates: list[dict[str, Any]] = []
        for r in conn:
            if r.get("id.orig_h") != src_ip or r.get("id.resp_h") != dst_ip:
                continue
            if dst_port is not None and r.get("id.resp_p") != dst_port:
                continue
            candidates.append(r)

        if candidates:
            if target_ts is None:
                c = sorted(candidates, key=lambda x: x.get("ts") or 0.0)[0]
                return Anchor(
                    uid=c.get("uid", ""),
                    ts=c.get("ts") or 0.0,
                    src_ip=c.get("id.orig_h", ""),
                    dst_ip=c.get("id.resp_h", ""),
                    dst_port=c.get("id.resp_p"),
                )

            # Find nearest timestamp candidate within tolerance.
            nearest = sorted(candidates, key=lambda x: abs((x.get("ts") or 0.0) - target_ts))[0]
            delta = abs((nearest.get("ts") or 0.0) - target_ts)
            if delta <= tolerance_s:
                return Anchor(
                    uid=nearest.get("uid", ""),
                    ts=nearest.get("ts") or 0.0,
                    src_ip=nearest.get("id.orig_h", ""),
                    dst_ip=nearest.get("id.resp_h", ""),
                    dst_port=nearest.get("id.resp_p"),
                )

    if target_ip:
        for r in conn:
            if r.get("id.resp_h") == target_ip or r.get("id.orig_h") == target_ip:
                return Anchor(
                    uid=r.get("uid", ""),
                    ts=r.get("ts") or 0.0,
                    src_ip=r.get("id.orig_h", ""),
                    dst_ip=r.get("id.resp_h", ""),
                    dst_port=r.get("id.resp_p"),
                )
    return None


def in_window(ts: float | None, start: float, end: float) -> bool:
    return ts is not None and start <= ts <= end


def extract_dns_preceding(dns: list[dict[str, Any]], anchor: Anchor, start: float, end: float) -> list[dict[str, Any]]:
    matches: list[dict[str, Any]] = []
    for row in dns:
        ts = row.get("ts")
        if not in_window(ts, start, anchor.ts):
            continue

        answers = str(row.get("answers", ""))
        if anchor.dst_ip and anchor.dst_ip in answers:
            matches.append(
                {
                    "time": ts_iso(ts),
                    "query": row.get("query"),
                    "qtype": row.get("qtype_name"),
                    "rcode": row.get("rcode_name"),
                    "answers": row.get("answers"),
                    "uid": row.get("uid"),
                }
            )
            continue

        if row.get("uid") == anchor.uid and in_window(ts, start, end):
            matches.append(
                {
                    "time": ts_iso(ts),
                    "query": row.get("query"),
                    "qtype": row.get("qtype_name"),
                    "rcode": row.get("rcode_name"),
                    "answers": row.get("answers"),
                    "uid": row.get("uid"),
                }
            )

    return matches[:30]


def extract_network_context(conn: list[dict[str, Any]], anchor: Anchor, start: float, end: float) -> dict[str, Any]:
    same_src = [r for r in conn if r.get("id.orig_h") == anchor.src_ip and in_window(r.get("ts"), start, end)]
    by_dst = Counter(r.get("id.resp_h") for r in same_src if r.get("id.resp_h"))
    by_port = Counter(r.get("id.resp_p") for r in same_src if r.get("id.resp_p") is not None)

    return {
        "same_src_conn_count": len(same_src),
        "top_dst": [{"value": k, "count": v} for k, v in by_dst.most_common(10)],
        "top_ports": [{"value": k, "count": v} for k, v in by_port.most_common(10)],
    }


def classify_connection(anchor: Anchor, conn: list[dict[str, Any]], beacons: list[dict[str, Any]]) -> list[str]:
    tags: list[str] = []

    if anchor.dst_port in (53, 123, 443, 80, 853, 5223):
        tags.append("common_service_port")
    else:
        tags.append("uncommon_port")

    if any(b.get("src") == anchor.src_ip and b.get("dst") == anchor.dst_ip and b.get("dst_port") == anchor.dst_port for b in beacons):
        tags.append("beacon_like_repetition")

    matching = [r for r in conn if r.get("id.resp_h") == anchor.dst_ip and r.get("id.resp_p") == anchor.dst_port]
    if len(matching) <= 2:
        tags.append("rare_destination")

    durations = [r.get("duration") for r in matching if isinstance(r.get("duration"), (int, float))]
    if durations and max(durations) >= 120:
        tags.append("long_lived_connection_seen")

    return tags


def correlate_anchor(anchor: Anchor, window_s: int, logs: dict[str, list[dict[str, Any]]], beacons: list[dict[str, Any]]) -> dict[str, Any]:
    start = anchor.ts - window_s
    end = anchor.ts + window_s

    def match(row: dict[str, Any]) -> bool:
        uid = row.get("uid")
        src = row.get("id.orig_h")
        dst = row.get("id.resp_h")
        if uid and uid == anchor.uid:
            return True
        return (src == anchor.src_ip and dst == anchor.dst_ip) or dst == anchor.dst_ip

    out: dict[str, Any] = {
        "anchor": {
            "uid": anchor.uid,
            "time": ts_iso(anchor.ts),
            "src_ip": anchor.src_ip,
            "dst_ip": anchor.dst_ip,
            "dst_port": anchor.dst_port,
        },
        "window": {
            "start": ts_iso(start),
            "end": ts_iso(end),
            "seconds": window_s,
        },
        "hits": {},
    }

    for name, rows in logs.items():
        selected = [r for r in rows if in_window(r.get("ts"), start, end) and match(r)]
        out["hits"][name] = {
            "count": len(selected),
            "sample": selected[:5],
        }

    out["dns_preceding"] = extract_dns_preceding(logs.get("dns", []), anchor, start, end)
    out["network_context"] = extract_network_context(logs.get("conn", []), anchor, start, end)
    out["classification"] = classify_connection(anchor, logs.get("conn", []), beacons)
    return out


def build_timeline(conn: list[dict[str, Any]], limit: int = 40) -> list[dict[str, Any]]:
    events = sorted((r for r in conn if r.get("ts") is not None), key=lambda x: float(x["ts"]))[:limit]
    out: list[dict[str, Any]] = []
    for r in events:
        out.append(
            {
                "time": ts_iso(r.get("ts")),
                "uid": r.get("uid"),
                "src": r.get("id.orig_h"),
                "dst": r.get("id.resp_h"),
                "port": r.get("id.resp_p"),
                "proto": r.get("proto"),
                "service": r.get("service"),
                "conn_state": r.get("conn_state"),
            }
        )
    return out


def build_graph(conn: list[dict[str, Any]], edge_limit: int = 100) -> dict[str, Any]:
    weights: Counter[tuple[str, str]] = Counter()
    for r in conn:
        src = r.get("id.orig_h")
        dst = r.get("id.resp_h")
        if not src or not dst or src == "-" or dst == "-":
            continue
        weights[(src, dst)] += 1

    top = weights.most_common(edge_limit)
    nodes = sorted({n for edge, _ in top for n in edge})
    edges = [{"src": s, "dst": d, "weight": w} for (s, d), w in top]
    return {"nodes": nodes, "edges": edges}


def write_dot(graph: dict[str, Any], out_path: Path) -> None:
    lines = ["digraph zeek_conn {", "  rankdir=LR;"]
    for n in graph.get("nodes", []):
        lines.append(f'  "{n}";')
    for e in graph.get("edges", []):
        lines.append(f'  "{e["src"]}" -> "{e["dst"]}" [label="{e["weight"]}"];')
    lines.append("}")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def bullet_summary(report: dict[str, Any]) -> list[str]:
    snap = report.get("snapshot", {})
    top_dst = snap.get("top_destinations", [])
    top_ports = snap.get("top_ports", [])
    beacons = report.get("beacon_candidates", [])

    bullets = [
        f"connections={snap.get('total_connections', 0)} unique_dst={snap.get('unique_destinations', 0)} unique_src={snap.get('unique_sources', 0)}",
        f"window={snap.get('time_start', 'n/a')}..{snap.get('time_end', 'n/a')}",
    ]

    if top_dst:
        bullets.append("top_dst=" + ", ".join(f"{x['value']}({x['count']})" for x in top_dst[:5]))
    if top_ports:
        bullets.append("top_ports=" + ", ".join(f"{x['value']}({x['count']})" for x in top_ports[:5]))

    if beacons:
        bullets.append(
            "beacons=" + ", ".join(
                f"{b['src']}->{b['dst']}:{b['dst_port']} hits={b['hits']} every~{b['avg_interval_s']}s"
                for b in beacons[:3]
            )
        )
    else:
        bullets.append("beacons=none_detected")

    target = report.get("target_context")
    if target:
        a = target.get("anchor", {})
        bullets.append(
            f"target uid={a.get('uid','')} dst={a.get('dst_ip','')}:{a.get('dst_port','')} time={a.get('time','')}"
        )
        tags = target.get("classification", [])
        if tags:
            bullets.append("target_tags=" + ",".join(tags[:6]))
    return bullets


def write_markdown(report: dict[str, Any], out_path: Path) -> None:
    snap = report.get("snapshot", {})
    target = report.get("target_context")
    beacons = report.get("beacon_candidates", [])

    lines: list[str] = []
    lines.append("# Audit + Zeek Integrated Summary")
    lines.append("")
    lines.append("## Snapshot")
    lines.append(f"- Connections: {snap.get('total_connections', 0)}")
    lines.append(f"- Unique sources: {snap.get('unique_sources', 0)}")
    lines.append(f"- Unique destinations: {snap.get('unique_destinations', 0)}")
    lines.append(f"- Time window: {snap.get('time_start', 'n/a')} to {snap.get('time_end', 'n/a')}")
    lines.append("")
    lines.append("## Top Destinations")
    for x in snap.get("top_destinations", [])[:10]:
        lines.append(f"- {x['value']}: {x['count']}")
    lines.append("")
    lines.append("## Top Ports")
    for x in snap.get("top_ports", [])[:10]:
        lines.append(f"- {x['value']}: {x['count']}")
    lines.append("")
    lines.append("## Beacon Candidates")
    if beacons:
        for b in beacons[:10]:
            lines.append(
                f"- {b['src']} -> {b['dst']}:{b['dst_port']} hits={b['hits']} interval~{b['avg_interval_s']}s jitter_cv={b['jitter_cv']}"
            )
    else:
        lines.append("- none")
    lines.append("")

    lines.append("## Targeted Correlation")
    if target:
        anchor = target.get("anchor", {})
        lines.append(
            f"- Anchor: uid={anchor.get('uid','')} src={anchor.get('src_ip','')} dst={anchor.get('dst_ip','')}:{anchor.get('dst_port','')} @ {anchor.get('time','')}"
        )
        lines.append(f"- Window: {target.get('window', {}).get('start', '')} .. {target.get('window', {}).get('end', '')}")
        lines.append("- Classification: " + ", ".join(target.get("classification", [])))
        lines.append("- DNS preceding matches:")
        dns_hits = target.get("dns_preceding", [])
        if dns_hits:
            for hit in dns_hits[:10]:
                lines.append(
                    f"  - {hit.get('time','')} query={hit.get('query','')} rcode={hit.get('rcode','')} answers={hit.get('answers','')}"
                )
        else:
            lines.append("  - none")
    else:
        lines.append("- No target anchor requested/found (use --uid or src/dst/port/timestamp args)")
    lines.append("")

    lines.append("## Suggested Directory Structure")
    lines.append("```text")
    lines.append("dev/")
    lines.append("  audit/")
    lines.append("    analysis/")
    lines.append("      zeek_snapshot.py")
    lines.append("    zlogs/")
    lines.append("      conn.log")
    lines.append("      dns.log")
    lines.append("      ssl.log")
    lines.append("      http.log")
    lines.append("      quic.log")
    lines.append("      files.log")
    lines.append("      weird.log")
    lines.append("    report/")
    lines.append("      zeek/")
    lines.append("        zeek-<run>.json")
    lines.append("        zeek-<run>.summary.txt")
    lines.append("        zeek-<run>.md")
    lines.append("        zeek-<run>.graph.dot")
    lines.append("```")

    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run(args: argparse.Namespace) -> dict[str, Any]:
    log_dir = Path(args.log_dir)
    conn = parse_zeek_tsv(log_dir / "conn.log")
    dns = parse_zeek_tsv(log_dir / "dns.log")
    ssl = parse_zeek_tsv(log_dir / "ssl.log")
    http = parse_zeek_tsv(log_dir / "http.log")
    quic = parse_zeek_tsv(log_dir / "quic.log")
    files = parse_zeek_tsv(log_dir / "files.log")
    weird = parse_zeek_tsv(log_dir / "weird.log")

    if not conn:
        raise SystemExit(f"No conn.log rows found in {log_dir}")

    timestamps = sorted(ts for ts in (r.get("ts") for r in conn) if ts is not None)

    dst_ips = [r.get("id.resp_h") for r in conn if r.get("id.resp_h")]
    src_ips = [r.get("id.orig_h") for r in conn if r.get("id.orig_h")]

    top_dst = top_counter(dst_ips, args.top_n)
    top_ports = top_counter([r.get("id.resp_p") for r in conn], args.top_n)
    top_services = top_counter([r.get("service") for r in conn], args.top_n)

    domain_counter = Counter(r.get("query") for r in dns if r.get("query") not in (None, "", "-"))
    top_domains = [{"value": k, "count": v} for k, v in domain_counter.most_common(args.top_n)]

    snapshot = {
        "log_dir": str(log_dir),
        "total_connections": len(conn),
        "unique_sources": len(set(src_ips)),
        "unique_destinations": len(set(dst_ips)),
        "time_start": ts_iso(timestamps[0] if timestamps else None),
        "time_end": ts_iso(timestamps[-1] if timestamps else None),
        "top_destinations": top_dst,
        "top_ports": top_ports,
        "top_services": top_services,
        "top_domains": top_domains,
        "log_rows": {
            "conn": len(conn),
            "dns": len(dns),
            "ssl": len(ssl),
            "http": len(http),
            "quic": len(quic),
            "files": len(files),
            "weird": len(weird),
        },
    }

    attribution: dict[str, Any] = {}
    for item in top_dst:
        ip = item["value"]
        if not isinstance(ip, str) or safe_private_ip(ip):
            continue
        obj = {"reverse_dns": reverse_dns(ip)}
        if args.enrich_ipinfo:
            obj.update(ipinfo(ip))
        attribution[ip] = obj

    logs = {
        "conn": conn,
        "dns": dns,
        "ssl": ssl,
        "http": http,
        "quic": quic,
        "files": files,
        "weird": weird,
    }

    target_ts = parse_ts_value(args.ts)
    beacons = detect_beacons(conn)
    anchor = find_anchor(
        conn=conn,
        target_uid=args.uid,
        target_ip=args.ip,
        src_ip=args.src_ip,
        dst_ip=args.dst_ip,
        dst_port=args.dst_port,
        target_ts=target_ts,
        tolerance_s=args.time_tolerance_seconds,
    )
    target_context = correlate_anchor(anchor, args.window_seconds, logs, beacons) if anchor else None

    graph = build_graph(conn, edge_limit=args.edge_limit)

    report = {
        "snapshot": snapshot,
        "attribution": attribution,
        "beacon_candidates": beacons,
        "timeline": build_timeline(conn, limit=args.timeline_limit),
        "target_context": target_context,
        "graph": graph,
    }

    return report


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Analyze Zeek logs for audit snapshots and correlations")
    p.add_argument("--log-dir", required=True)
    p.add_argument("--out-json", required=True)
    p.add_argument("--out-bullets")
    p.add_argument("--out-dot")
    p.add_argument("--out-md")
    p.add_argument("--uid")
    p.add_argument("--ip")
    p.add_argument("--src-ip")
    p.add_argument("--dst-ip")
    p.add_argument("--dst-port", type=int)
    p.add_argument("--ts", help="Anchor timestamp (epoch seconds or ISO-8601)")
    p.add_argument("--time-tolerance-seconds", type=int, default=90)
    p.add_argument("--window-seconds", type=int, default=120)
    p.add_argument("--top-n", type=int, default=10)
    p.add_argument("--edge-limit", type=int, default=100)
    p.add_argument("--timeline-limit", type=int, default=40)
    p.add_argument("--enrich-ipinfo", action="store_true")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    report = run(args)

    out_json = Path(args.out_json)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    bullets = bullet_summary(report)
    if args.out_bullets:
        Path(args.out_bullets).write_text("\n".join(f"- {b}" for b in bullets) + "\n", encoding="utf-8")
    else:
        print("\n".join(f"- {b}" for b in bullets))

    if args.out_dot:
        write_dot(report.get("graph", {}), Path(args.out_dot))

    if args.out_md:
        write_markdown(report, Path(args.out_md))


if __name__ == "__main__":
    main()
