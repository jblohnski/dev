<!-- dev-component: id=ops-pf kind=support group=sys desc="PF firewall toolkit (macOS) with DNS hardening anchors and helpers" -->

# pfkit (macOS)

PF toolkit for macOS that locks DNS to audited targets, blocks multicast noise, and keeps Apple defaults intact by loading a single anchor.

## Layout

- `bin/`: operational entrypoints (`pfkit-install`, `pfkit-apply`, `pfkit-status`, `pfkit-uninstall`, watch helpers).
- `anchors/`: anchor template rendered into `/etc/pf.anchors/pfkit.anchor`.
- `config/`: environment inputs (`pfkit.env`) used by render/apply.

## Quick start

```bash
sudo ./bin/pfkit-install.sh
sudo ./bin/pfkit-apply.sh
```

Validate:

```bash
sudo ./bin/pfkit-status.sh
sudo pfctl -a pfkit -sr
sudo tcpdump -ni en0 port 53 or port 5353
```

## Config knobs (`config/pfkit.env`)

- `EXT_IF` — optional override; defaults to the interface for the default route.
- `DNS_MODE` — `router` (force DNS to gateway) or `direct` (force to specific IPs).
- `DNS_ALLOWED` — space-delimited IPs when `DNS_MODE=direct`.
- `ALLOW_LAN_CIDRS` — LAN ranges allowed.
- `BLOCK_MDNS` — block mDNS (default 1).
- `BLOCK_DOT` — block DoT/DoQ on 853 (default 1).
- `BLOCK_QUIC` — block QUIC/HTTP3 on UDP 443 (default 1).

## Behaviors

- Keeps Apple default inbound posture (no blanket `pass in all`).
- Blocks outbound UDP/TCP 53 except allowed DNS targets.
- Blocks outbound UDP 5353 with logging.
- Blocks DoT/DoQ on 853 when enabled.
- Blocks QUIC/HTTP3 on UDP 443 when enabled so browsers stay on TCP 443.
- Logs every explicit block rule in the anchor.

## Uninstall

```bash
sudo ./bin/pfkit-uninstall.sh
```

## Live monitoring

- Live PF status: `sudo ./bin/pfkit-status.sh`
- DNS-only watch: `sudo ./bin/pfkit-watch-dns.sh`
- PF block tail: `sudo ./bin/pfkit-watch-blocks.sh`
