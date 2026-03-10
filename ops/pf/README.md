<!-- @component: ops-pf -->
<!-- @kind: support -->
<!-- @desc: PF firewall toolkit and operational rule wiring -->
<!-- @tags: ops pf support -->

# pfkit_v2 (macOS)

Goal:
- Force **all DNS** to a single, auditable path (router or chosen resolvers).
- Block noisy **mDNS (UDP/5353)** multicast.
- Keep browsing/YouTube/Twitter working.

This kit **does not overwrite** `/etc/pf.conf`. It installs an **anchor** and adds a single `anchor` + `load anchor` line to `/etc/pf.conf` (with backups), so Apple defaults remain intact.

## Quick start

```bash
cd pfkit_v2
sudo ./bin/pfkit-install.sh
sudo ./bin/pfkit-apply.sh
```

Validate:

```bash
sudo pfctl -sr | sed -n '1,200p'
sudo pfctl -sa | grep -i Status
sudo tcpdump -ni en0 port 53 or port 5353
```

## Config

Edit `config/pfkit.env`:
- `EXT_IF` (optional) — default auto-detect.
- `DNS_MODE` — `router` (force DNS to default gateway) or `direct` (force to specific resolvers).
- `DNS_ALLOWED` — space-separated IPs if `DNS_MODE=direct`.
- `ALLOW_LAN_CIDRS` — LAN ranges allowed.

## What it enforces

- Default inbound posture stays **Apple-default** (pfkit does not add blanket `pass in all`).
- Blocks outbound **UDP/TCP 53** except allowed DNS targets.
- Blocks outbound **UDP 5353** to multicast (IPv4 + IPv6).
- Optional: block outbound **DoT (853)** except allowed targets.

## Uninstall

```bash
sudo ./bin/pfkit-uninstall.sh
```

## Live monitoring

DNS only:

```bash
sudo ./bin/pfkit-watch-dns.sh
```

PF log tail (requires pflog):

```bash
sudo ./bin/pfkit-watch-blocks.sh
```
