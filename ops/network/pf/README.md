<!-- dev-component: id=ops-pf kind=subcomponent group=net desc="PF firewall toolkit (macOS) with DNS hardening anchors and helpers" -->

# pfkit (macOS)

PF toolkit for macOS that locks DNS to audited targets, blocks multicast noise, and can optionally restrict HTTPS to a tight Google sign-in hostname set via a single anchor.

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
- `BASELINE_PROFILE` — terse statement of the intended egress posture shown in `pfs`.
- `BLOCK_MDNS` — block mDNS on the primary interface (default 1).
- `BLOCK_APPLE_P2P` — block AWDL / llw continuity traffic (default 1).
- `BLOCK_UTUN` — block `utun*` interfaces instead of passing them (default 1).
- `BLOCK_DOT` — block DoT/DoQ on 853 (default 1).
- `BLOCK_QUIC` — block QUIC/HTTP3 on UDP 443 (default 1).
- `GOOGLE_ENDPOINT_MODE` — `hosts` or `manual`.
- `GOOGLE_ALLOWED` — manual space-delimited Google IPv4 CIDRs when `GOOGLE_ENDPOINT_MODE=manual`.
- `GOOGLE_ALLOWED_HOSTS` — hostname allowlist resolved to `/32` IPv4 entries for Google sign-in lockdown mode.
- `EXTRA_HTTPS_ALLOWED` — manual extra HTTPS CIDRs to allow alongside Google.
- `EXTRA_HTTPS_ALLOWED_HOSTS` — narrow hostname exceptions resolved to `/32` CIDRs at apply time.
- `BLACKLIST_IN_CIDRS` — space-delimited source IPs/CIDRs to drop inbound on `EXT_IF`.
- `BLACKLIST_OUT_CIDRS` — space-delimited destination IPs/CIDRs to block outbound on `EXT_IF`.

## Behaviors

- Keeps Apple default inbound posture (no blanket `pass in all`).
- Blocks outbound UDP/TCP 53 except allowed DNS targets.
- Blocks mDNS by default for a tighter host posture.
- Blocks `utun*` by default and keeps AWDL / llw disabled unless you explicitly unblock them.
- Supports separate inbound and outbound IP/CIDR blacklists ahead of the main policy.
- Resolves a small Google sign-in hostname set into `/32`s for Google-only HTTPS mode and caches the results for `pfs`.
- Allows a narrow hostname-based HTTPS exception list for sites that must work without opening the broader web.
- Blocks DoT/DoQ on 853 when enabled.
- Blocks QUIC/HTTP3 on UDP 443 when enabled so browsers stay on TCP 443.
- Can restrict HTTPS to the configured Google hostname set without dumping a huge CIDR inventory in `pfs`.
- Logs every explicit block rule in the anchor.
- Logs allowed DNS with `log (all)` so `pflog0` shows the PF decision path for approved resolvers.
- Adds `pfkit:` rule labels so `pfctl -s labels` exposes per-rule counters even when live capture is quiet.
- Background block logging writes text logs under `~/dev/logs/pfkit/`, and `pfs` tails that file directly.

## Status

- Live PF status: `sudo pfs`
- Raw block-log tail: `sudo pfs --tail`
- Optional raw CIDR dump: `sudo pfs --cidrs`

## Blacklist examples

```bash
BLACKLIST_IN_CIDRS="198.51.100.7 203.0.113.0/24"
BLACKLIST_OUT_CIDRS="198.51.100.7 203.0.113.0/24"
```

Apply after editing:

```bash
sudo pfo
```
