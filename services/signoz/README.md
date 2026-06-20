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
| `signoz-schema-migrator` | `signoz/signoz-otel-collector` | One-shot schema init (bootstrap + sync + async) |
| `signoz-init-clickhouse` | `clickhouse/clickhouse-server` | One-shot: installs the `histogramQuantile` UDF binary |

> **Note:** the consolidated SigNoz no longer ships a standalone
> `signoz/signoz-schema-migrator` image; schema migration runs from the
> `signoz/signoz-otel-collector` image via `migrate bootstrap && migrate sync up
> && migrate async up`.

> **Note:** older SigNoz docs describe separate `query-service`, `frontend`, and
> `alertmanager` containers with the UI on `:3301`. That layout is deprecated for
> new installs; this stack uses the consolidated image with the UI on `:8080`.

## Files

- `docker-compose.signoz.yml` — overlay included by `deploy.sh` on rocketman.
- `otel-collector-config.yaml` — main collector pipeline.
- `clickhouse-config.xml`, `clickhouse-users.xml` — ClickHouse server/user tuning.
- `clickhouse-cluster.xml` — ZooKeeper + single-node `cluster` topology (mounted
  into `config.d/`); required for the `ON CLUSTER` schema migrations.
- `clickhouse-custom-function.xml` — registers the `histogramQuantile` UDF.
- `alertmanager.yml` — alert routing (configured in Phase 6).
- `prometheus.yml` — scrape targets for the collector's prometheus receiver.
- `dashboards/` — seeded SigNoz dashboards (Phase 6).

## Enable / disable

The stack is included via `deploy.sh rocketman`, which appends
`-f services/signoz/docker-compose.signoz.yml` to the compose invocation. Remove
that line in `deploy.sh` to disable telemetry without touching app services.

## Security note

ClickHouse runs with `CLICKHOUSE_SKIP_USER_SETUP=1` and a passwordless `default`
user (matching SigNoz upstream). This is safe here because ClickHouse publishes
**no host port** — it is reachable only by other containers on the `cys-service`
bridge. Do not add a host port mapping for it.

Set `SIGNOZ_JWT_SECRET` (and `SIGNOZ_BIND_ADDR` to the tailnet IP) before any
live deploy; the compose default for the JWT secret is the upstream placeholder.

## Raspberry Pi (arm64) note

ClickHouse arm64 images require an ARMv8.2-A CPU. Verify the host supports it
before deploying; older Pi 4 silicon can crash with "illegal instruction". Pin
`CLICKHOUSE_VERSION` to a tag confirmed working on the target hardware.
