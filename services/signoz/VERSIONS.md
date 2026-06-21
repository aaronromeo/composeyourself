# Pinned image versions (verified at branch creation)

These are the concrete pins decided in Phase 0. They are surfaced as env vars in
`.env.example`; this file records the rationale and the verified-latest values.

| Component | Env var | Pin | Source |
|---|---|---|---|
| SigNoz (UI + query + alertmanager) | `SIGNOZ_VERSION` | `v0.129.0` | github.com/SigNoz/signoz latest release |
| SigNoz OTel collector | `SIGNOZ_OTEL_COLLECTOR_VERSION` | `v0.144.5` | github.com/SigNoz/signoz-otel-collector latest |
| SigNoz schema migrator | (matches collector) | `v0.144.5` | same repo |
| ClickHouse | `CLICKHOUSE_VERSION` | `25.5.6` | SigNoz v0.129.0 ships 25.5.6; 24.1.2 too old for v0.144.5 migrator |
| ZooKeeper | `ZOOKEEPER_VERSION` | `3.7.1` | `signoz/zookeeper` |
| otelcol-contrib (SPL edge) | `OTELCOL_CONTRIB_VERSION` | `0.135.0` | otel/opentelemetry-collector-contrib stable line |
| cAdvisor | `CADVISOR_VERSION` | `v0.57.0` | github.com/google/cadvisor latest |
| node-exporter | `NODE_EXPORTER_VERSION` | `v1.11.1` | github.com/prometheus/node_exporter latest |
| postgres-exporter | `POSTGRES_EXPORTER_VERSION` | `v0.19.1` | prometheus-community/postgres_exporter latest |
| redis-exporter | `REDIS_EXPORTER_VERSION` | `v1.86.0` | oliver006/redis_exporter latest |

## Notes

- **otelcol-contrib**: `0.135.0` is the latest GA tag in the stable release line
  (the bare `0.155.x` tags on Docker Hub are nightlies — do not use). Confirm the
  exact stable tag on Docker Hub before first deploy.
- **ClickHouse 25.5.6 required**: the signoz-otel-collector v0.144.5 schema
  migrator emits `JSON(max_dynamic_paths=100)` DDL that ClickHouse 24.x does not
  understand (fails: code 62 syntax error). Pin to 25.5.6 or later.
  rocketman is x86_64 (Intel i5-4570T) — no arm64 constraint applies.
- SigNoz's collector and schema-migrator versions are released together and must
  match; bump them as a pair.
