# Sweetpaintedlady edge collector (otelcol-contrib)

Lightweight OpenTelemetry Collector that runs on **sweetpaintedlady** (DigitalOcean
VPS), gathers local infra signals, and forwards them over Tailscale to the SigNoz
collector on rocketman.

See [`../../OTEL_SPEC.md`](../../OTEL_SPEC.md) §5.3 for the design.

## What it collects

- **filelog** — Docker container logs (`/var/lib/docker/containers/*/*-json.log`).
- **prometheus** — scrapes local `cadvisor`, `node-exporter`, and Authelia
  (`:9959/metrics`).
- **otlp** — accepts OTLP from any local service that speaks it (e.g. Caddy).

## Where it ships

Exports OTLP/gRPC to `${ROCKETMAN_TAILSCALE_HOST}:${ROCKETMAN_OTLP_GRPC_PORT}`
(default `rocketman:4317`) with `tls.insecure: true` (Tailscale provides the
encryption) plus `sending_queue` + `retry_on_failure` so telemetry buffers
through brief tailnet outages.

## Files

- `config.yaml` — the edge collector pipeline.

## Enable / disable

Added to `docker-compose.sweetpaintedlady.yml`. Remove the `otelcol-agent`,
`cadvisor`, and `node-exporter` service blocks to disable.
