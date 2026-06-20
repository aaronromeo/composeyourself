# OpenTelemetry Observability — Specification

Status: **Draft for review**
Owner: rocketman host
Repo: `composeyourself-grafana`

---

## 1. Goal

Introduce end-to-end OpenTelemetry observability (traces, metrics, logs) across
the `composeyourself` deployment, with:

- All signals collected, stored, and viewed on **rocketman**.
- All cross-host signal traffic flowing **only over Tailscale**.
- A single UI (**SigNoz**) for traces, metrics, and logs with correlation.
- First-party instrumentation of our own services (`yt-dlp`, `announcements`,
  `swole`); container/host-level scraping for third-party services
  (`immich`, `postgres`, `redis`, `openwebui`, `caddy`, `authelia`).
- Set-and-forget operation: stable images, pinned versions, predictable
  upgrades via `update.sh`.

Out of scope for v1 (parking lot):
- HA / clustered ClickHouse.
- Offsite backup of telemetry data (separate B2 effort, already on roadmap).
- Alertmanager → external pagers (Discord/email comes after baseline is green).
- Public Grafana/SigNoz exposure with Authelia (Tailscale-only for now).

---

## 2. High-level architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│ sweetpaintedlady (DigitalOcean)                                        │
│                                                                        │
│  caddy ──┐                                                             │
│  authelia┤                                                             │
│  openwebui┘                                                            │
│       │                                                                │
│       │  docker logs / scraped metrics / native OTLP where supported   │
│       ▼                                                                │
│  ┌──────────────────────┐                                              │
│  │ otelcol-contrib      │  (lightweight agent, ~80 MB)                 │
│  │ - filelog receiver   │                                              │
│  │ - docker stats recv  │                                              │
│  │ - prom scrape recv   │                                              │
│  │ - otlp receiver      │                                              │
│  │ - batch/memory_limit │                                              │
│  └──────────┬───────────┘                                              │
│             │ OTLP/gRPC :4317 (compressed, retried)                    │
└─────────────┼──────────────────────────────────────────────────────────┘
              │
              │ Tailscale tailnet (WireGuard, encrypted)
              │
┌─────────────┼──────────────────────────────────────────────────────────┐
│ rocketman   ▼                                                          │
│                                                                        │
│  ┌────────────────────────────────────────────────────┐                │
│  │ SigNoz OTel Collector (bound to Tailscale IP only) │                │
│  │ :4317 OTLP/gRPC   :4318 OTLP/HTTP                  │                │
│  └──────────────┬─────────────────────────────────────┘                │
│                 │                                                      │
│   ┌─────────────┼────────────────────────────────┐                     │
│   │ also receives from local services:           │                     │
│   │  - yt-dlp  ─ OTLP (SDK)                      │                     │
│   │  - announcements ─ OTLP (SDK)                │                     │
│   │  - swole   ─ OTLP (SDK)                      │                     │
│   │  - cAdvisor / node_exporter (Prom scrape)    │                     │
│   │  - postgres_exporter / redis_exporter        │                     │
│   │  - Docker logs via filelog receiver          │                     │
│   │  - immich (its own /metrics endpoint scrape) │                     │
│   └──────────────────────────────────────────────┘                     │
│                 │                                                      │
│                 ▼                                                      │
│  ┌──────────────────────────┐    ┌──────────────────────┐              │
│  │ ClickHouse + ZooKeeper   │◄──►│ SigNoz query-service │              │
│  └──────────────────────────┘    └──────────┬───────────┘              │
│                                              │                         │
│                                              ▼                         │
│                                  ┌─────────────────────┐               │
│                                  │ SigNoz frontend     │ :3301         │
│                                  │ (UI for L/M/T)      │               │
│                                  └─────────────────────┘               │
│                                                                        │
│  Reachable only via tailnet: http://rocketman:3301                     │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Components & versions

All images pinned in `.env` via `SIGNOZ_VERSION`, `OTELCOL_VERSION`, etc.

| Component | Image | Where | Purpose |
|---|---|---|---|
| `signoz-clickhouse` | `clickhouse/clickhouse-server:24.x` | rocketman | Time-series store for traces, metrics, logs |
| `signoz-zookeeper` | `bitnami/zookeeper:3.9` | rocketman | ClickHouse coordination |
| `signoz-schema-migrator` | `signoz/signoz-schema-migrator:<ver>` | rocketman | Init ClickHouse schemas |
| `signoz-query-service` | `signoz/query-service:<ver>` | rocketman | API for the UI |
| `signoz-frontend` | `signoz/frontend:<ver>` | rocketman | Web UI on :3301 |
| `signoz-alertmanager` | `signoz/alertmanager:<ver>` | rocketman | Alert routing (configured later) |
| `signoz-otel-collector` | `signoz/signoz-otel-collector:<ver>` | rocketman | Main collector (OTLP in, ClickHouse out) |
| `signoz-otel-collector-metrics` | same image, separate config | rocketman | Sidecar collector for internal SigNoz metrics |
| `otelcol-agent` | `otel/opentelemetry-collector-contrib:<ver>` | sweetpaintedlady | Edge agent, forwards to rocketman |
| `cadvisor` | `gcr.io/cadvisor/cadvisor:<ver>` | rocketman + SPL | Container metrics |
| `node-exporter` | `prom/node-exporter:<ver>` | rocketman + SPL | Host metrics |
| `postgres-exporter` | `prometheuscommunity/postgres-exporter` | rocketman | Postgres metrics for immich DB |
| `redis-exporter` | `oliver006/redis_exporter` | rocketman | Redis metrics for immich cache |

---

## 4. Port allocation (rocketman, Tailscale-bound)

| Port | Bound to | Purpose |
|---|---|---|
| `3301` | tailnet IP | SigNoz frontend (UI) |
| `4317` | tailnet IP | OTLP/gRPC ingest |
| `4318` | tailnet IP | OTLP/HTTP ingest |
| `8888` | 127.0.0.1 | Collector internal telemetry (not exposed) |
| `9100` | tailnet IP | node_exporter (optional, scraped locally) |
| `8081` | 127.0.0.1 | cAdvisor (scraped locally) |

Sweetpaintedlady binds nothing externally for telemetry; its collector
**egresses** OTLP to `rocketman.<tailnet>:4317`.

Tailscale binding pattern: use `network_mode: host` for the collector
container and explicit `--listen-addr` flags pointing at the tailnet IP, OR a
`tailscale serve` rule. Decision deferred to implementation Phase 0.5.

---

## 5. Signal flow per source

### 5.1 Own services (SDK-instrumented)

`yt-dlp`, `announcements`, `swole` get an OTel SDK added in their respective
submodule repos. They emit OTLP/gRPC directly to the collector.

Env vars injected via docker-compose:

```
OTEL_EXPORTER_OTLP_ENDPOINT=http://signoz-otel-collector:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_SERVICE_NAME=<service>
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=prod,host.name=rocketman
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=1.0  # full sampling at home-server scale
OTEL_METRIC_EXPORT_INTERVAL=15000
OTEL_LOGS_EXPORTER=otlp
```

For local rocketman services they reach the collector via the
`cys-service` docker network (`signoz-otel-collector:4317`).

### 5.2 Third-party services on rocketman

- **immich-server**: scrape `:2283/api/server/statistics` (or whatever
  immich exposes); ship logs via Docker `json-file` driver tailed by
  collector `filelog` receiver.
- **postgres (immich_postgres)**: `postgres-exporter` sidecar; logs via filelog.
- **redis (immich_redis)**: `redis-exporter` sidecar; logs via filelog.
- **immich-machine-learning**: logs via filelog; no metrics endpoint to scrape.

### 5.3 Sweetpaintedlady services (via SPL edge collector)

- **caddy**: has an OTel exporter; configure `tracing` block + JSON access log
  shipped via filelog.
- **authelia**: no native OTLP; ship logs only (filelog). Metrics endpoint
  exists at `:9959/metrics` — scrape via Prom receiver.
- **openwebui**: no native OTLP; logs via filelog only.
- **cAdvisor/node_exporter** on SPL: scraped by SPL edge collector.

All of the above flow through the SPL edge collector → OTLP/gRPC over
Tailscale → rocketman.

### 5.4 Infrastructure

- **cAdvisor** + **node_exporter** on both hosts → scraped by local collector.
- **Docker daemon logs** → filelog receiver on `/var/lib/docker/containers/*/*.log`.

---

## 6. Storage & retention

Configured in ClickHouse TTLs (SigNoz exposes these as env vars):

| Signal | Retention | Rationale |
|---|---|---|
| Logs | 14 days | Incident review window |
| Traces | 7 days | Debugging recent issues |
| Metrics | 30 days | Trend / capacity planning |

ClickHouse data directory: `/mnt/storage/signoz/clickhouse`
ZooKeeper data: `/mnt/storage/signoz/zookeeper`
Alertmanager data: `/mnt/storage/signoz/alertmanager`

Expected steady-state disk usage at home-server volume (~1 M spans/day, ~5 M
log lines/day, 1 K active series): roughly 5–15 GB total. Plenty of margin on
`/mnt/storage`.

---

## 7. Security & access

- SigNoz frontend (`:3301`) is reachable **only via Tailscale**, same model as
  yt-dlp/immich. No Caddy/Authelia in front of it.
- OTLP ingest ports (`:4317`/`:4318`) bound to the Tailscale interface IP, not
  `0.0.0.0`. Local docker-network traffic uses the docker DNS name.
- SigNoz has its own user auth (built-in). First admin user is created on
  first UI visit. We treat this as defense-in-depth on top of Tailscale ACLs.
- Telemetry contains potentially sensitive data (URLs, headers). All transit
  is either inside the host bridge network or over WireGuard via Tailscale.

---

## 8. Resource budget (rocketman)

| Component | Memory limit | CPU limit |
|---|---|---|
| ClickHouse | 4 GB | 2.0 |
| ZooKeeper | 512 MB | 0.5 |
| query-service | 512 MB | 1.0 |
| frontend | 128 MB | 0.5 |
| alertmanager | 128 MB | 0.25 |
| signoz-otel-collector | 1 GB | 1.0 |
| signoz-otel-collector-metrics | 256 MB | 0.5 |
| cAdvisor | 256 MB | 0.5 |
| node-exporter | 64 MB | 0.25 |
| postgres-exporter | 64 MB | 0.25 |
| redis-exporter | 64 MB | 0.25 |
| **Total** | **~7 GB** | **~6.5 vCPU** |

Rocketman has ~15.4 GiB RAM, so this leaves ~8 GB for immich + the rest. If
ClickHouse pressure shows up, we tune `max_server_memory_usage` down.

On sweetpaintedlady, the edge collector is the only addition: ~150 MB memory
limit, 0.25 CPU. cAdvisor + node-exporter add ~300 MB combined.

---

## 9. Configuration layout

```
composeyourself-grafana/
├── docker-compose.yml                     # unchanged (tailscale only)
├── docker-compose.rocketman.yml           # + signoz block, exporters
├── docker-compose.sweetpaintedlady.yml    # + edge collector, exporters
├── services/
│   ├── signoz/
│   │   ├── README.md
│   │   ├── docker-compose.signoz.yml      # signoz services as overlay
│   │   ├── clickhouse-config.xml
│   │   ├── clickhouse-users.xml
│   │   ├── otel-collector-config.yaml
│   │   ├── otel-collector-metrics-config.yaml
│   │   ├── alertmanager.yml
│   │   └── dashboards/                    # seeded SigNoz dashboards (JSON)
│   ├── otelcol-spl/
│   │   ├── README.md
│   │   └── config.yaml                    # SPL edge collector config
│   ├── cadvisor/                          # tiny config or just compose
│   ├── node-exporter/
│   ├── postgres-exporter/
│   │   └── queries.yaml
│   └── redis-exporter/
└── .env.example                           # + SIGNOZ_* and OTEL_* vars
```

Pattern: SigNoz services in their own overlay file
(`services/signoz/docker-compose.signoz.yml`) included via deploy.sh:

```bash
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.rocketman.yml -f services/signoz/docker-compose.signoz.yml"
```

This keeps the SigNoz stack self-contained and easy to disable.

---

## 10. New environment variables (`.env.example`)

```bash
# =========================================================================
# OBSERVABILITY (rocketman)
# =========================================================================
SIGNOZ_VERSION=0.x.y                       # pinned SigNoz release
CLICKHOUSE_VERSION=24.x
OTELCOL_CONTRIB_VERSION=0.x.y              # SPL edge collector
CADVISOR_VERSION=v0.49.x
NODE_EXPORTER_VERSION=v1.8.x
POSTGRES_EXPORTER_VERSION=v0.15.x
REDIS_EXPORTER_VERSION=v1.62.x

# Where SigNoz/ClickHouse stores its data on rocketman
SIGNOZ_DATA_LOCATION=/mnt/storage/signoz

# Retention overrides (days)
SIGNOZ_LOGS_RETENTION_DAYS=14
SIGNOZ_TRACES_RETENTION_DAYS=7
SIGNOZ_METRICS_RETENTION_DAYS=30

# Tailscale IP of rocketman, used by SPL edge collector
# (set during first deploy; can also use MagicDNS name `rocketman`)
ROCKETMAN_TAILSCALE_HOST=rocketman
ROCKETMAN_OTLP_GRPC_PORT=4317
ROCKETMAN_OTLP_HTTP_PORT=4318

# Per-service OTel resource attributes (optional override)
OTEL_RESOURCE_ATTRIBUTES_BASE=deployment.environment=prod
```

---

## 11. Acceptance criteria

The feature is done when:

1. `./deploy.sh rocketman` brings up the full SigNoz stack alongside existing
   services with no manual steps beyond a populated `.env`.
2. `./deploy.sh sweetpaintedlady` brings up the SPL edge collector + exporters.
3. `http://rocketman:3301` (over Tailscale) loads the SigNoz UI.
4. Traces from `yt-dlp`, `announcements`, `swole` are visible in the
   Services list with non-zero RED metrics.
5. Container metrics for all containers (both hosts) appear in the metrics
   explorer.
6. Logs from all containers (both hosts) appear in the logs explorer with
   correct service labels.
7. Killing a container produces a visible gap and recovery in the dashboards.
8. ClickHouse data survives a `docker compose down/up` cycle.
9. README updated with: stack overview, how to access UI, where to find
   common dashboards, troubleshooting tips.
10. `update.sh rocketman` pulls newer pinned SigNoz images cleanly.

---

## 12. Open questions parked for implementation

- Exact SigNoz release pin (latest stable at start of Phase 1).
- Whether to use SigNoz's bundled compose file as a git submodule under
  `services/signoz` vs. hand-rolled overlay. Leaning hand-rolled for
  visibility, with their compose as reference.
- Whether `network_mode: host` for the collector vs. dual-binding via a
  Tailscale sidecar pattern is cleaner on this host. Resolved during Phase 0.5.
- Sampling strategy if trace volume explodes (probably never at home-server
  scale, but `parentbased_traceidratio` is configured to allow tuning).
