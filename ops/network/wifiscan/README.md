<!-- dev-component: id=wifiscan kind=support group=net desc="Native Wi-Fi scanner backed by CoreWLAN for modern macOS" -->

# wifiscan

Native Wi-Fi scan component for current macOS releases where `airport` and shell-only scans are unreliable.

Use `./wifiscan.sh` to query nearby networks through CoreWLAN. On modern macOS, Terminal or iTerm may need Location Services permission before scan results are exposed.

Examples:

```bash
./wifiscan.sh
./wifiscan.sh --json
./wifiscan.sh --limit 10
./wifiscan.sh --interface en0
```

Notes:

- Runs as `user`; `sudo` is usually not the fix for Wi-Fi scan visibility.
- The wrapper prefers a compiled `wifiscan-bin` in this directory if present, otherwise it runs `main.swift` with `swift`.
- If CoreWLAN does not expose an interface or scan results, the tool prints diagnostics instead of pretending there are zero networks.

Optional build:

```bash
swiftc -framework CoreWLAN -framework CoreLocation -o ./wifiscan-bin ./main.swift
```
