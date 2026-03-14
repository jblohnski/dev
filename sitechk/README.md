<!-- @component: sitechk -->
<!-- @kind: support -->
<!-- @desc: Site identity checks across DNS, TLS, and HTTP -->
<!-- @keywords: audit web tls dns http -->

# sitechk

`sitechk` verifies basic site identity signals across DNS resolution, TLS
certificate data, and HTTP headers.

## Files

- `sitechk.sh`: identity check entrypoint

## Requirements

- `dig`
- `openssl`
- `curl`
- `awk`
- `sed`
- `grep`
- `whois` or `host` for ownership hints

## Usage

```sh
./sitechk.sh kagi.com
./sitechk.sh https://kagi.com
```

The script emits:

- DNS A and AAAA records
- TLS certificate subject, issuer, dates, and SANs
- HTTP response headers
- An aggregate summary and a JSON payload for downstream tooling
