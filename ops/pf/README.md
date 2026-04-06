<!-- dev-component: id=ops-pf kind=support group=sys desc="PF firewall toolkit (macOS) with DNS hardening anchors and helpers" -->

# pfkit (macOS)

PF toolkit for macOS that locks DNS to audited targets, blocks multicast noise, and keeps Apple defaults intact by loading a single anchor.

## Layout

- `bin/`: operational entrypoints (`pfkit-install`, `pfkit-apply`, `pfkit-status`, `pfkit-uninstall`, watch helpers).
- `anchors/`: anchor template rendered into `/etc/pf.anchors/pfkit.anchor`.
- `config/`: environment inputs (`pfkit.env`) used by render/apply.

## Quick start

```bash
sudo ./bin/pfkit.sh start
```

Validate:

```bash
sudo ./bin/pfkit-status.sh
sudo pfctl -a pfkit -sr
sudo pfctl -s labels | grep 'pfkit:'
sudo ./bin/pfkit.sh logs status
sudo ./bin/pfkit-watch-dns.sh --iface en0
```

## Control Surface

- `pf start` — install wiring if needed, then apply the tracked pfkit rules
- `pf stop` — empty the `pfkit` anchor without disabling PF globally
- `pf status` — show PF state, pfkit rules, label counters, and log-capture status
- `pf update` — re-render and reload the tracked pfkit anchor
- `pf revert` — restore backed-up system `pf.conf` state and remove pfkit wiring
- `pf logs start|stop|status|tail|cat|path|clear` — manage the background block logger

Why `stop` is not `pfctl -d`:

- `pfctl -d` disables the packet filter globally, which is wider than “stop pfkit”.
- `pf stop` only unloads the `pfkit` anchor so Apple/system PF usage outside this anchor is left alone.
- Existing states may still flow until they expire; `stop` is a rules unload, not a global state purge.

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
- Logs allowed DNS with `log (all)` so `pflog0` shows the PF decision path for approved resolvers.
- Adds `pfkit:` rule labels so `pfctl -s labels` exposes per-rule counters even when live capture is quiet.
- Background block logging writes text logs under `~/Library/Logs/pfkit/` for later `lnav`/grep use.

## Uninstall

```bash
sudo ./bin/pfkit-uninstall.sh
```

## Live monitoring

- Live PF status: `sudo ./bin/pfkit-status.sh`
- Unified control entrypoint: `sudo ./bin/pfkit.sh help`
- DNS-only watch (PF decisions on `pflog0`): `sudo ./bin/pfkit-watch-dns.sh`
- DNS-only watch (raw interface traffic): `sudo ./bin/pfkit-watch-dns.sh --iface en0`
- PF block tail (`pflog0` lines containing `block`): `sudo ./bin/pfkit-watch-blocks.sh`
- PF block logger to file: `sudo ./bin/pfkit.sh logs start`
