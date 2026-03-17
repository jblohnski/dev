<!-- @component: netshot -->
<!-- @kind: support -->
<!-- @desc: Packet capture and Zeek snapshot helper -->
<!-- @keywords: netshot audit network zeek capture -->

# netshot

`netshot` is a self-contained network snapshot tool that captures packets with
`tcpdump`, analyzes the capture with `zeek`, and prints a small summary.

## Files

- `netshot.sh`: capture and analysis entrypoint
- `analyze.py`: parses Zeek logs and prints the summary
- `output/`: timestamped run artifacts

## Requirements

- `tcpdump`
- `zeek`
- `python3`
- `sudo` access if you are not running as root

## Usage

```sh
./netshot.sh
./netshot.sh 15
NETSHOT_INTERFACE=en0 ./netshot.sh 15
```

The duration argument is optional and defaults to `40` seconds.
On macOS, `netshot` auto-detects the default network interface instead of using
`tcpdump -i any`. If auto-detection is wrong, set `NETSHOT_INTERFACE`.

Each run creates a directory under `output/` containing:

- `capture.pcap`
- `tcpdump.stderr.log` if `tcpdump` reported an error
- `zeek/` logs produced from that capture

The printed summary includes:

- Top talkers
- Top destinations
- TLS servers observed
