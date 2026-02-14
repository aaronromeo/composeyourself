# Tailscale Service

This service runs Tailscale inside Docker to provide secure remote access to the host.

## Required Environment

- `TS_AUTHKEY`: Auth key used for automatic login.

## Optional Environment

- `TS_EXTRA_ARGS`: Extra `tailscale up` arguments (for example `--advertise-exit-node`).

## Notes

- Uses `network_mode: host` for full host connectivity.
- Requires `NET_ADMIN` and `SYS_MODULE` capabilities and access to `/dev/net/tun`.
