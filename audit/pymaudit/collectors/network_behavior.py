from __future__ import annotations

import random
import re
import time
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple, Any, Iterable

from ..util import run_cmd, which

_LOSF_SPLIT_RE = re.compile(r"\s+")
_TCPDUMP_LINE_RE = re.compile(r"^(?P<ts>\d+\.\d+)\s+(?P<body>.*)$")

def _split_host_port(s: str) -> Tuple[Optional[str], Optional[int]]:
    s = s.strip()
    if s == "*":
        return "*", None
    if ":" not in s:
        return s, None
    host, port_s = s.rsplit(":", 1)
    host = host.strip()
    port_s = port_s.strip()
    if port_s.isdigit():
        return host, int(port_s)
    return s, None

def _parse_lsof(out: str) -> List[Dict[str, Any]]:
    lines = [ln.rstrip("\n") for ln in out.splitlines() if ln.strip()]
    if not lines:
        return []
    header_idx = 0
    if not lines[0].startswith("COMMAND"):
        for i, ln in enumerate(lines[:10]):
            if ln.startswith("COMMAND"):
                header_idx = i
                break
    lines = lines[header_idx:]
    if not lines or not lines[0].startswith("COMMAND"):
        return []
    header = _LOSF_SPLIT_RE.split(lines[0].strip())
    try:
        name_i = header.index("NAME")
    except ValueError:
        name_i = len(header) - 1

    recs: List[Dict[str, Any]] = []
    for ln in lines[1:]:
        parts = _LOSF_SPLIT_RE.split(ln.strip())
        if len(parts) <= name_i:
            continue
        proc = parts[0]
        pid = int(parts[1]) if parts[1].isdigit() else None
        user = parts[2] if len(parts) > 2 else None
        name = " ".join(parts[name_i:])

        proto = None
        for tok in parts:
            if tok in ("TCP", "UDP"):
                proto = tok.lower()

        m = re.search(r"\(([^)]+)\)\s*$", name)
        state = m.group(1).strip().lower() if m else None
        name_wo = name[:m.start()].strip() if m else name

        laddr = lport = raddr = rport = None
        if "->" in name_wo:
            left, right = name_wo.split("->", 1)
            laddr, lport = _split_host_port(left)
            raddr, rport = _split_host_port(right)
        else:
            laddr, lport = _split_host_port(name_wo)

        recs.append({
            "proto": proto,
            "state": state,
            "pid": pid,
            "proc": proc,
            "user": user,
            "laddr": laddr,
            "lport": lport,
            "raddr": raddr,
            "rport": rport,
        })
    return recs

def _split_tcpdump_addr(s: str) -> Tuple[str, Optional[int]]:
    s = s.strip()
    if "." in s:
        host, port_s = s.rsplit(".", 1)
        if port_s.isdigit():
            return host, int(port_s)
    return s, None

def _parse_tcpdump_lines(lines: Iterable[str]) -> List[Dict[str, Any]]:
    pkts: List[Dict[str, Any]] = []
    for ln in lines:
        ln = ln.strip()
        if not ln:
            continue
        m = _TCPDUMP_LINE_RE.match(ln)
        if not m:
            continue
        ts = float(m.group("ts"))
        body = m.group("body")
        if body.startswith("IP6 "):
            body2 = body[4:]
        elif body.startswith("IP "):
            body2 = body[3:]
        else:
            continue
        if " > " not in body2:
            continue
        left, rest = body2.split(" > ", 1)
        if ":" in rest:
            right_addr, tail = rest.split(":", 1)
        else:
            right_addr, tail = rest, ""
        src_ip, src_port = _split_tcpdump_addr(left)
        dst_ip, dst_port = _split_tcpdump_addr(right_addr)
        l4 = None
        if " UDP" in rest or " UDP," in rest:
            l4 = "udp"
        elif " Flags" in rest or " ack" in rest or " tcp" in rest:
            l4 = "tcp"
        pkts.append({
            "ts": ts,
            "l4": l4 or "unknown",
            "src_ip": src_ip,
            "src_port": src_port,
            "dst_ip": dst_ip,
            "dst_port": dst_port,
        })
    return pkts

def guess_default_interface() -> Optional[str]:
    if which("route"):
        r = run_cmd(["route", "get", "default"], timeout_s=5)
        if r.rc == 0:
            for ln in r.out.splitlines():
                if "interface:" in ln:
                    return ln.split("interface:", 1)[1].strip()
    if which("ip"):
        r = run_cmd(["ip", "route", "show", "default"], timeout_s=5)
        if r.rc == 0:
            m = re.search(r"\bdev\s+(\S+)", r.out)
            if m:
                return m.group(1)
    return None

def list_active_tunnels(limit: int = 1) -> List[str]:
    if which("netstat"):
        r = run_cmd(["netstat", "-ib"], timeout_s=8)
        if r.rc == 0:
            counts: Dict[str, int] = {}
            for ln in r.out.splitlines():
                if not ln or ln.startswith("Name"):
                    continue
                parts = ln.split()
                if not parts:
                    continue
                name = parts[0]
                if not name.startswith("utun"):
                    continue
                ints = [int(p) for p in parts if p.isdigit()]
                if ints:
                    counts[name] = max(counts.get(name, 0), max(ints))
            return [k for k, _ in sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:limit]]
    return []

@dataclass
class NetBehaviorConfig:
    burst_seconds: int = 5
    bursts: int = 2
    jitter_min_s: float = 2.0
    jitter_max_s: float = 6.0
    interfaces: Optional[List[str]] = None
    tcpdump_timeout_s: int = 20

def collect_network_behavior(cfg: NetBehaviorConfig) -> Dict[str, Any]:
    info: Dict[str, Any] = {
        "config": {
            "burst_seconds": cfg.burst_seconds,
            "bursts": cfg.bursts,
            "jitter_min_s": cfg.jitter_min_s,
            "jitter_max_s": cfg.jitter_max_s,
            "interfaces": cfg.interfaces,
        },
        "errors": [],
        "warnings": [],
    }

    sockets: List[Dict[str, Any]] = []
    if not which("lsof"):
        info["errors"].append("lsof not found; cannot map sockets to processes.")
    else:
        tcp = run_cmd(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN,ESTABLISHED"], timeout_s=10)
        udp = run_cmd(["lsof", "-nP", "-iUDP"], timeout_s=10)
        sockets = _parse_lsof(tcp.out) + _parse_lsof(udp.out)
        info["lsof"] = {
            "tcp_rc": tcp.rc,
            "udp_rc": udp.rc,
            "socket_count": len(sockets),
            "tcp_err_head": tcp.err.strip().splitlines()[:3],
            "udp_err_head": udp.err.strip().splitlines()[:3],
        }
        if tcp.rc != 0 or udp.rc != 0:
            info["warnings"].append("lsof returned non-zero; results may be incomplete (try sudo).")

    sock_index: Dict[Tuple[str, int, str], Tuple[int, str]] = {}
    listeners: List[Dict[str, Any]] = []
    for s in sockets:
        proto = (s.get("proto") or "").lower()
        if not proto or s.get("pid") is None or s.get("lport") is None:
            continue
        key = (str(s.get("laddr")), int(s.get("lport")), proto)
        sock_index[key] = (int(s["pid"]), str(s["proc"]))
        if (s.get("state") or "").lower() == "listen":
            listeners.append(s)

    if cfg.interfaces:
        ifaces = list(cfg.interfaces)
    else:
        ifaces = []
        d = guess_default_interface()
        if d:
            ifaces.append(d)
        for t in list_active_tunnels(limit=1):
            if t not in ifaces:
                ifaces.append(t)
        if not ifaces:
            ifaces = ["any"] if which("tcpdump") else []
    info["interfaces"] = ifaces

    bursts_meta: List[Dict[str, Any]] = []
    packets_all: List[Dict[str, Any]] = []

    if not which("tcpdump"):
        info["errors"].append("tcpdump not found; cannot sample packet metadata.")
    else:
        for bi in range(cfg.bursts):
            for iface in ifaces:
                argv = ["tcpdump", "-i", iface, "-nn", "-tt", "-q", "-c", "200"]
                timeout_s = max(cfg.burst_seconds + 5, 10)
                if which("timeout"):
                    argv = ["timeout", str(cfg.burst_seconds), *argv]
                    timeout_s = cfg.tcpdump_timeout_s
                res = run_cmd(argv, timeout_s=timeout_s)
                pkts = _parse_tcpdump_lines(res.out.splitlines())
                for p in pkts:
                    p["iface"] = iface
                packets_all.extend(pkts)
                bursts_meta.append({
                    "iface": iface,
                    "rc": res.rc,
                    "runtime_s": res.runtime_s,
                    "packet_count": len(pkts),
                    "stderr_head": res.err.strip().splitlines()[:5],
                })
                if res.rc not in (0, 124):
                    if "permission" in (res.err or "").lower():
                        info["warnings"].append(f"tcpdump on {iface} likely needs sudo.")
            if bi < cfg.bursts - 1:
                time.sleep(random.uniform(cfg.jitter_min_s, cfg.jitter_max_s))

    info["bursts"] = bursts_meta

    # Attribution + timing distributions
    def proc_key(pid: Optional[int], proc: Optional[str]) -> str:
        if pid is None or proc is None:
            return "unknown"
        return f"{pid}/{proc}"

    proc_stats: Dict[str, Dict[str, Any]] = {}
    flow_stats: Dict[str, Dict[str, Any]] = {}
    last_ts_by_proc: Dict[str, float] = {}
    last_ts_by_flow: Dict[str, float] = {}

    for p in packets_all:
        l4 = p.get("l4") or "unknown"
        pid = proc = None

        # try src local
        sp = p.get("src_port")
        dp = p.get("dst_port")
        if sp is not None:
            k = (str(p.get("src_ip")), int(sp), l4)
            if k in sock_index:
                pid, proc = sock_index[k]
        if pid is None and dp is not None:
            k = (str(p.get("dst_ip")), int(dp), l4)
            if k in sock_index:
                pid, proc = sock_index[k]

        pk = proc_key(pid, proc)
        ps = proc_stats.setdefault(pk, {
            "pid": pid,
            "proc": proc,
            "packet_count": 0,
            "flows": set(),
            "unique_remotes": set(),
            "unique_ports": set(),
            "ifaces": set(),
            "inter_arrival_s": [],
        })
        ps["packet_count"] += 1
        ps["ifaces"].add(str(p.get("iface")))

        src = f"{p.get('src_ip')}:{p.get('src_port')}"
        dst = f"{p.get('dst_ip')}:{p.get('dst_port')}"
        flow = f"{l4} {min(src, dst)} <-> {max(src, dst)}"
        ps["flows"].add(flow)

        remote_ip = None
        remote_port = None
        if pid is not None:
            local_is_src = False
            if sp is not None and (str(p.get("src_ip")), int(sp), l4) in sock_index:
                local_is_src = True
            if local_is_src:
                remote_ip = p.get("dst_ip"); remote_port = dp
            else:
                remote_ip = p.get("src_ip"); remote_port = sp
        if remote_ip is not None:
            ps["unique_remotes"].add(str(remote_ip))
        if remote_port is not None:
            try:
                ps["unique_ports"].add(int(remote_port))
            except Exception:
                pass

        ts = float(p["ts"])
        if pk in last_ts_by_proc:
            ps["inter_arrival_s"].append(ts - last_ts_by_proc[pk])
        last_ts_by_proc[pk] = ts

        fs = flow_stats.setdefault(flow, {"l4": l4, "packet_count": 0, "inter_arrival_s": []})
        fs["packet_count"] += 1
        if flow in last_ts_by_flow:
            fs["inter_arrival_s"].append(ts - last_ts_by_flow[flow])
        last_ts_by_flow[flow] = ts

    def summarize(vals: List[float]) -> Dict[str, Any]:
        vals = [v for v in vals if v >= 0]
        vals.sort()
        n = len(vals)
        if n == 0:
            return {"count": 0}
        def pct(p: float) -> float:
            idx = int(round((p / 100.0) * (n - 1)))
            return float(vals[idx])
        return {"count": n, "min": float(vals[0]), "p50": pct(50), "p90": pct(90), "p99": pct(99), "max": float(vals[-1])}

    proc_out: List[Dict[str, Any]] = []
    for k, v in proc_stats.items():
        proc_out.append({
            "key": k,
            "pid": v["pid"],
            "proc": v["proc"],
            "packet_count": v["packet_count"],
            "flow_count": len(v["flows"]),
            "unique_remote_count": len(v["unique_remotes"]),
            "unique_port_count": len(v["unique_ports"]),
            "ifaces": sorted(list(v["ifaces"])),
            "timing": summarize(v["inter_arrival_s"]),
            "unique_remotes": sorted(list(v["unique_remotes"]))[:200],
            "flows": sorted(list(v["flows"]))[:200],
        })
    proc_out.sort(key=lambda x: x["packet_count"], reverse=True)

    flow_out: List[Dict[str, Any]] = []
    for flow, v in flow_stats.items():
        flow_out.append({
            "flow": flow,
            "l4": v["l4"],
            "packet_count": v["packet_count"],
            "timing": summarize(v["inter_arrival_s"]),
        })
    flow_out.sort(key=lambda x: x["packet_count"], reverse=True)

    listener_out = [{
        "proto": s.get("proto"),
        "pid": s.get("pid"),
        "proc": s.get("proc"),
        "laddr": s.get("laddr"),
        "lport": s.get("lport"),
    } for s in listeners]

    info["results"] = {
        "listeners": listener_out,
        "top_processes": proc_out[:10],
        "top_flows": flow_out[:20],
        "unknown_packet_count": next((p["packet_count"] for p in proc_out if p["key"] == "unknown"), 0),
        "packet_total": len(packets_all),
    }
    return info
