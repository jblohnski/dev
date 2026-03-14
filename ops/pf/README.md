<!-- @component: ops-pf -->
<!-- @kind: support -->
<!-- @desc: PF firewall toolkit (macOS) with DNS hardening anchors and helpers -->
<!-- @keywords: ops pf firewall dns macos support -->

# pfkit (macOS)

PF toolkit for macOS that locks DNS to audited targets, blocks multicast noise, and keeps Apple defaults intact by loading a single anchor.

## Layout

- `bin/`: operational entrypoints (`pfkit-install`, `pfkit-apply`, `pfkit-uninstall`, watch helpers).
- `anchors/`: anchor template rendered into `/etc/pf.anchors/pfkit.anchor`.
- `config/`: environment inputs (`pfkit.env`) used by render/apply.

## Quick start

```bash
sudo ./bin/pfkit-install.sh
sudo ./bin/pfkit-apply.sh
```

Validate:

```bash
sudo pfctl -sr | sed -n '1,120p'
sudo pfctl -sa | grep -i Status
sudo tcpdump -ni en0 port 53 or port 5353
```

## Config knobs (`config/pfkit.env`)

- `EXT_IF` — optional override; defaults to the interface for the default route.
- `DNS_MODE` — `router` (force DNS to gateway) or `direct` (force to specific IPs).
- `DNS_ALLOWED` — space-delimited IPs when `DNS_MODE=direct`.
- `ALLOW_LAN_CIDRS` — LAN ranges allowed.
- `BLOCK_MDNS` — block mDNS (default 1).
- `BLOCK_DOT` — block DoT except allowed (default 0).

## Behaviors

- Keeps Apple default inbound posture (no blanket `pass in all`).
- Blocks outbound UDP/TCP 53 except allowed DNS targets.
- Blocks outbound UDP 5353 multicast.
- Optional DoT (853) blocking when enabled.

## Uninstall

```bash
sudo ./bin/pfkit-uninstall.sh
```

## Live monitoring

- DNS-only watch: `sudo ./bin/pfkit-watch-dns.sh`
- PF block tail: `sudo ./bin/pfkit-watch-blocks.sh`
