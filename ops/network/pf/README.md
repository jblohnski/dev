<!-- dev-component: id=ops-pf kind=subcomponent group=net desc="PF firewall toolkit (macOS) with DNS hardening anchors and helpers" -->

# pfkit (macOS)

PF toolkit for macOS that locks DNS to audited targets, blocks multicast noise, blocks arbitrary UDP by default, and can optionally restrict HTTPS to a tight Google sign-in hostname set via a single anchor.

## Layout

- `bin/`: the `pfkit` dispatcher plus private helpers used by its subcommands.
- `anchors/`: anchor template rendered into `/etc/pf.anchors/pfkit.anchor`.
- `config/`: environment inputs (`pfkit.env`) used by render/apply.

Public legend aliases are compact; their names still point at the `pfkit-*` wrappers.
Private helper scripts do not declare command metadata.

## Quick start

```bash
sudo pfon
```

Validate:

```bash
sudo pflg report
```

## Control Surface

- `(pfon) pfkit-start` — repair files/wiring, apply tracked rules, enable PF, and start block logging
- `(pfof) pfkit-stop` — stop block logging, unload the `pfkit` anchor, and disable PF globally
- `(pfst) pfkit-status` — show whether PFKit, PF rules, logger, and `pflog0` are running
- `(pfup) pfkit-update` — repair files/wiring and apply tracked PFKit rules without changing logger state
- `(pflg) pfkit-logs` — report, tail, print, or clear retained block-log capture files

## PF Mapping

- `pfkit-status` is read-only: it checks global PF state, the loaded `pfkit` anchor, logger pid, and `pflog0`.
- `pfkit-update` repairs repo/system wiring, renders the anchor, loads it with `pfctl -a pfkit -f`, and enables PF if needed.
- `pfkit-start` runs `pfkit-update`, ensures `pflog0` exists, and starts the block-log capture.
- `pfkit-stop` stops capture, clears the `pfkit` anchor, and disables global PF with `pfctl -d`.
- `pfkit-logs` reads retained PFKit log files; it is not a raw `pfctl` passthrough.

Why `pfkit-stop` maps to a real PF shutdown:

- `pfkit-stop` calls `pfctl -d` after stopping pfkit logging and clearing the `pfkit` anchor.
- This is intentionally wider than “stop pfkit”: the packet filter is turned off for the host.
- `pfkit-start` is the path that brings PF back up and reapplies the tracked anchor.

## Config knobs (`config/pfkit.env`)

- `EXT_IF` — optional override; defaults to the interface for the default route.
- `DNS_MODE` — `router` (force DNS to gateway) or `direct` (force to specific IPs).
- `DNS_ALLOWED` — space-delimited IPs when `DNS_MODE=direct`.
- `ALLOW_LAN_CIDRS` — LAN ranges allowed.
- `BASELINE_PROFILE` — terse statement of the intended egress posture shown in PFKit reports.
- `ALLOW_TCP_PORTS` — space-delimited outbound TCP ports allowed in normal mode.
- `ALLOW_UDP_PORTS` — optional extra outbound UDP ports allowed in addition to DNS.
- `BLOCK_ARBITRARY_UDP` — block outbound UDP except DNS and `ALLOW_UDP_PORTS` (default 1).
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
- Restricts normal-mode TCP egress to configured ports instead of allowing the full web by default.
- Blocks arbitrary outbound UDP by default, leaving DNS as the primary UDP exception.
- Blocks mDNS by default for a tighter host posture.
- Blocks `utun*` by default and keeps AWDL / llw disabled unless you explicitly unblock them.
- Supports separate inbound and outbound IP/CIDR blacklists ahead of the main policy.
- Resolves a small Google sign-in hostname set into `/32`s for Google-only HTTPS mode and caches the results for reports.
- Allows a narrow hostname-based HTTPS exception list for sites that must work without opening the broader web.
- Blocks DoT/DoQ on 853 when enabled.
- Blocks QUIC/HTTP3 on UDP 443 when enabled so browsers stay on TCP 443.
- Can restrict HTTPS to the configured Google hostname set without dumping a huge CIDR inventory in normal reports.
- Logs every explicit block rule in the anchor.
- Logs allowed DNS with `log (all)` so `pflog0` shows the PF decision path for approved resolvers.
- Adds `pfkit:` rule labels so `pfctl -s labels` exposes per-rule counters even when live capture is quiet.
- Background block logging writes text logs under `~/dev/logs/pfkit/`, and `pfkit-logs` reads that file directly.

## Policy Notes

- The shared traffic review behind this update pointed to policy looseness, not compromise.
- `pfkit` is still host-level PF policy, not per-process containment for Firefox.
- The default normal-mode posture is now surgical: DNS only to approved resolvers, TCP only to `ALLOW_TCP_PORTS`, and UDP blocked unless explicitly excepted.

## Logs

- Short retained-log report: `sudo pflg report`
- Running/not-running status: `sudo pfst`
- Raw block-log tail: `sudo pflg tail`
- Full retained block log: `sudo pflg cat`
- Log path: `sudo pflg path`

## Blacklist examples

```bash
BLACKLIST_IN_CIDRS="198.51.100.7 203.0.113.0/24"
BLACKLIST_OUT_CIDRS="198.51.100.7 203.0.113.0/24"
```

Apply after editing:

```bash
sudo pfup
```
