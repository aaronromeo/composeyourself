# SigNoz observability stack (rocketman)

Self-contained OpenTelemetry backend (traces, metrics, logs) for the
`composeyourself` deployment. Reachable **only over Tailscale** at
`http://rocketman:8080`.

See [`../../OTEL_SPEC.md`](../../OTEL_SPEC.md) and
[`../../OTEL_PLAN.md`](../../OTEL_PLAN.md) for the full design.

## Architecture

Current SigNoz (v0.1xx) ships as a **single `signoz/signoz` image** that bundles
the query service, web UI, and alertmanager. The stack here is:

| Container | Image | Purpose |
|---|---|---|
| `signoz` | `signoz/signoz` | UI + query service + alertmanager (UI on `:8080`) |
| `signoz-clickhouse` | `clickhouse/clickhouse-server` | Trace/metric/log store |
| `signoz-zookeeper` | `signoz/zookeeper` | ClickHouse coordination |
| `signoz-otel-collector` | `signoz/signoz-otel-collector` | OTLP ingest -> ClickHouse |
| `signoz-schema-migrator` | `signoz/signoz-schema-migrator` | One-shot schema init (sync + async) |

> **Note:** older SigNoz docs describe separate `query-service`, `frontend`, and
> `alertmanager` containers with the UI on `:3301`. That layout is deprecated for
> new installs; this stack uses the consolidated image with the UI on `:8080`.

## Files

- `docker-compose.signoz.yml` — overlay included by `deploy.sh` on rocketman.
- `otel-collector-config.yaml` — main collector pipeline.
- `clickhouse-config.xml`, `clickhouse-users.xml` — ClickHouse tuning.
- `alertmanager.yml` — alert routing (configured in Phase 6).
- `prometheus.yml` — scrape targets for the collector's prometheus receiver.
- `dashboards/` — seeded SigNoz dashboards (Phase 6).

## Enable / disable

The stack is included via `deploy.sh rocketman`, which appends
`-f services/signoz/docker-compose.signoz.yml` to the compose invocation. Remove
that line in `deploy.sh` to disable telemetry without touching app services.

## Raspberry Pi (arm64) note

ClickHouse arm64 images require an ARMv8.2-A CPU. Verify the host supports it
before deploying; older Pi 4 silicon can crash with "illegal instruction". Pin
`CLICKHOUSE_VERSION` to a tag confirmed working on the target hardware.
