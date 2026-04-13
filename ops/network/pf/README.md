<!-- dev-component: id=ops-pf kind=subcomponent group=net desc="PF firewall toolkit (macOS) with DNS hardening anchors and helpers" -->

# pfkit (macOS)

PF toolkit for macOS that locks DNS to audited targets, blocks multicast noise, and can restrict HTTPS to Google-owned endpoints by loading a single anchor.

## Layout

- `bin/`: public entrypoints (`pfo`, `pfs`, `pfk`) plus internal helpers used by those wrappers.
- `anchors/`: anchor template rendered into `/etc/pf.anchors/pfkit.anchor`.
- `config/`: environment inputs (`pfkit.env`) used by render/apply.

## Quick start

```bash
sudo pfo
```

Validate:

```bash
sudo pfs
```

## Control Surface

- `pfo` — install wiring if needed, apply the tracked pfkit rules, and start block logging
- `pfs` — show concise PF on/off state plus recent block-log output
- `pfk` — empty the `pfkit` anchor and stop block logging without disabling PF globally

Why `pfk` is not `pfctl -d`:

- `pfctl -d` disables the packet filter globally, which is wider than “stop pfkit”.
- `pfk` only unloads the `pfkit` anchor so Apple/system PF usage outside this anchor is left alone.
- Existing states may still flow until they expire; `pfk` is a rules unload, not a global state purge.

## Config knobs (`config/pfkit.env`)

- `EXT_IF` — optional override; defaults to the interface for the default route.
- `DNS_MODE` — `router` (force DNS to gateway) or `direct` (force to specific IPs).
- `DNS_ALLOWED` — space-delimited IPs when `DNS_MODE=direct`.
- `ALLOW_LAN_CIDRS` — LAN ranges allowed.
- `BLOCK_MDNS` — block mDNS on the primary interface (default 0).
- `ALLOW_APPLE_P2P` — pass AWDL / llw continuity traffic without logging noise (default 1).
- `BLOCK_UTUN` — block `utun*` interfaces instead of passing them (default 0).
- `BLOCK_DOT` — block DoT/DoQ on 853 (default 1).
- `BLOCK_QUIC` — block QUIC/HTTP3 on UDP 443 (default 1).
- `GOOGLE_ENDPOINT_MODE` — `official_default_domains` or `manual`.
- `GOOGLE_ALLOWED` — manual space-delimited Google IPv4 CIDRs when `GOOGLE_ENDPOINT_MODE=manual`.

## Behaviors

- Keeps Apple default inbound posture (no blanket `pass in all`).
- Blocks outbound UDP/TCP 53 except allowed DNS targets.
- Allows normal mDNS by default so Bonjour / AirDrop / local discovery do not flood the block log.
- Passes `awdl0`, `llw0`, and `utun*` by default so PF does not fight Apple-managed local transport.
- Can still block mDNS or utun traffic explicitly through config knobs when you want a tighter diagnostic posture.
- Blocks DoT/DoQ on 853 when enabled.
- Blocks QUIC/HTTP3 on UDP 443 when enabled so browsers stay on TCP 443.
- Can restrict HTTPS to Google-owned default-domain/service ranges computed from Google's official published IP datasets.
- Logs every explicit block rule in the anchor.
- Logs allowed DNS with `log (all)` so `pflog0` shows the PF decision path for approved resolvers.
- Adds `pfkit:` rule labels so `pfctl -s labels` exposes per-rule counters even when live capture is quiet.
- Background block logging writes text logs under `~/dev/logs/pfkit/`, and `pfs` tails that file directly.

## Uninstall

```bash
sudo ./bin/pfkit-uninstall.sh
```

## Live monitoring

- Live PF status: `sudo pfs`
- Unified control entrypoint: `sudo ./bin/pfkit.sh help`
- DNS-only watch (PF decisions on `pflog0`): `sudo ./bin/pfkit-watch-dns.sh`
- DNS-only watch (raw interface traffic): `sudo ./bin/pfkit-watch-dns.sh --iface en0`
- PF block tail (`pflog0` lines containing `block`): `sudo ./bin/pfkit-watch-blocks.sh`
