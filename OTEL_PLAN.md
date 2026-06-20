# OpenTelemetry Observability — Implementation Plan

Companion to [`OTEL_SPEC.md`](./OTEL_SPEC.md). Phases are sequential; each
phase ends with something demoable and safe to leave running.

> **Status:** Phases 0–3 implemented as config on branch `feat/otel-observability`
> (deploy/verify steps still require the live hosts). The SigNoz layout was updated
> to the current consolidated architecture: a single `signoz/signoz` image (UI on
> **`8080`**, not `3301`), schema migration via the `signoz-otel-collector` image,
> exporter `signozclickhousemetrics`, and processor `signozspanmetrics/delta`.
> Phases 4–7 (submodule instrumentation, immich, dashboards/alerts, docs) remain.

---

## Phase 0 — Prep & decisions (no infra changes)

**Goal:** lock concrete versions, file layout, and tailnet binding.

- [x] Pick SigNoz release pin → `v0.129.0` (see `services/signoz/VERSIONS.md`).
- [x] Pick `otelcol-contrib` release pin → `0.135.0`.
- [x] Decide Tailscale bind mechanism → **Option A, adapted:** keep the
      containers on the `cys-service` bridge (so local services resolve
      `signoz-otel-collector` by DNS) and bind the externally-reachable ports
      (UI `8080`, OTLP `4317`/`4318`) to the tailnet IP via `SIGNOZ_BIND_ADDR`
      instead of `network_mode: host` (which would break the bridge DNS).
- [x] Create branch: `feat/otel-observability`.
- [x] Add `services/signoz/` and `services/otelcol-spl/` directories with
      READMEs (and exporter config dirs).

**Exit criteria:** branch open, no behavior change, repo structure ready.

---

## Phase 1 — SigNoz stack on rocketman

**Goal:** SigNoz UI reachable on `http://rocketman:8080` over Tailscale, with
empty data. No producers yet.

1. Write `services/signoz/docker-compose.signoz.yml` containing (current
   consolidated layout):
   - `signoz-clickhouse`
   - `signoz-zookeeper`
   - `signoz-init-clickhouse` (one-shot: installs the histogramQuantile UDF)
   - `signoz-schema-migrator` (one-shot, `signoz-otel-collector` image running
     `migrate bootstrap/sync/async`; depends_on clickhouse healthy)
   - `signoz-otel-collector`
   - `signoz` (consolidated UI + query service + alertmanager, UI on :8080)
   - All on the `cys-service` bridge network.
   - Resource limits per SPEC §8.
2. Write `services/signoz/clickhouse-config.xml`, `clickhouse-cluster.xml`,
   `clickhouse-users.xml`, `clickhouse-custom-function.xml`, `alertmanager.yml`
   — start from SigNoz upstream defaults, redact unused bits.
3. Write `services/signoz/otel-collector-config.yaml`:
   - receivers: `otlp` (grpc+http on tailnet IP), `prometheus` (internal),
     `filelog` (commented stub for now)
   - processors: `batch`, `memory_limiter`, `resourcedetection/system`,
     `signozspanmetrics/delta`
   - exporters: `clickhousetraces`, `clickhouselogsexporter`,
     `signozclickhousemetrics`
4. Update `.env.example` with new vars (see SPEC §10).
5. Update `deploy.sh` to include the signoz overlay file when host is
   `rocketman`.
6. Add `/mnt/storage/signoz/{clickhouse,zookeeper,alertmanager}` mkdir step
   in deploy.sh's rocketman setup block (with appropriate chown).
7. Deploy. Verify:
   - `docker compose ... ps` shows all signoz containers healthy.
   - `curl http://localhost:8080` returns the UI.
   - From sweetpaintedlady: `curl http://rocketman:4317` connects (gRPC
     handshake error is fine — proves reachability).
   - First-time SigNoz admin user can be created.

**Exit criteria:** empty SigNoz UI loads over Tailscale; ClickHouse persists
across restart.

---

## Phase 2 — Local infra signals (rocketman)

**Goal:** see real metrics and logs without changing any application code.

1. Add to `docker-compose.rocketman.yml`:
   - `cadvisor` (scrapes Docker, exposes `:8081/metrics`).
   - `node-exporter` (host metrics, `:9100/metrics`).
   - `postgres-exporter` (env-driven, targets `immich_postgres`).
   - `redis-exporter` (env-driven, targets `immich_redis`).
2. Update `otel-collector-config.yaml`:
   - Add `prometheus` receiver scrape configs for cadvisor, node-exporter,
     postgres-exporter, redis-exporter (15s interval).
   - Enable `filelog` receiver reading
     `/var/lib/docker/containers/*/*-json.log` with the Docker JSON parser.
   - Mount `/var/lib/docker/containers:/var/lib/docker/containers:ro` into
     the collector container.
3. Set Docker logging driver in `docker-compose.rocketman.yml` defaults to
   `json-file` with rotation (size=10m, max-file=3) so the filelog tail
   doesn't grow unboundedly. (Already the implicit default but make it
   explicit.)
4. Redeploy. Verify in SigNoz UI:
   - Hosts list shows `rocketman`.
   - Container metrics graphs populated for every rocketman container.
   - Logs explorer shows entries tagged by `container_name`.

**Exit criteria:** zero-code-change observability of every container + host
on rocketman.

---

## Phase 3 — Sweetpaintedlady edge collector

**Goal:** SPL ships infra signals to rocketman over Tailscale.

1. Write `services/otelcol-spl/config.yaml`:
   - receivers: `prometheus` (scraping local cadvisor/node-exporter/authelia),
     `filelog` (Docker container logs), `otlp` (for caddy or any local
     OTLP-capable service).
   - processors: `batch`, `memory_limiter`, `resourcedetection/system`,
     `attributes` (inject `host.name=sweetpaintedlady`).
   - exporters: `otlp` to `${ROCKETMAN_TAILSCALE_HOST}:4317`, with
     `tls.insecure: true` (Tailscale encrypts) and `retry_on_failure` +
     `sending_queue` for resilience.
2. Add to `docker-compose.sweetpaintedlady.yml`:
   - `otelcol-agent` (image `otel/opentelemetry-collector-contrib:<ver>`).
   - `cadvisor`, `node-exporter` (same images as rocketman).
   - Mount Docker socket + containers dir (read-only) into the collector.
3. Caddy: add the OTel exporter to its Caddyfile if a clean port exists; if
   not, ship JSON access logs via filelog only.
4. Authelia: add `AUTHELIA_TELEMETRY_METRICS_ENABLED=true` and scrape `:9959`.
5. Redeploy SPL. Verify:
   - SigNoz UI hosts list now shows both `rocketman` and `sweetpaintedlady`.
   - Caddy, openwebui, authelia containers' logs visible.
   - Authelia metrics scraped (login attempts, etc.).

**Exit criteria:** both hosts visible in SigNoz; logs from every container
arrive within seconds.

---

## Phase 4 — Application instrumentation (own services)

**Goal:** real traces with RED metrics for the services we own.

This phase touches submodules; commits go to each submodule repo, not the
parent.

For each of `services/announcements`, `services/yt-dlp`, `services/swole`:

1. Identify language/framework (likely Python or Go based on existing
   Dockerfiles).
2. Add OTel SDK + auto-instrumentation packages:
   - Python: `opentelemetry-distro`, `opentelemetry-exporter-otlp` +
     `opentelemetry-bootstrap --action=install` in the Dockerfile.
   - Go: `go.opentelemetry.io/otel`, `go.opentelemetry.io/contrib/...`
     manual setup.
3. Add OTLP env vars in the corresponding compose service block:
   ```yaml
   environment:
     - OTEL_SERVICE_NAME=announcements
     - OTEL_EXPORTER_OTLP_ENDPOINT=http://signoz-otel-collector:4317
     - OTEL_EXPORTER_OTLP_PROTOCOL=grpc
     - OTEL_RESOURCE_ATTRIBUTES=deployment.environment=prod,host.name=rocketman
     - OTEL_LOGS_EXPORTER=otlp
     - OTEL_METRIC_EXPORT_INTERVAL=15000
   ```
4. For Python services using Flask/FastAPI: wrap entrypoint with
   `opentelemetry-instrument`.
5. Commit + tag in each submodule, bump submodule pointer in parent repo.
6. Redeploy. Verify in SigNoz UI:
   - Services list shows `announcements`, `yt-dlp`, `swole`.
   - "Operations" tab shows endpoints with p50/p95/p99 latency and error rate.
   - Clicking a slow request shows a full trace.
   - From a trace span, "View logs" jumps to the correlated log lines.

**Exit criteria:** RED metrics and traces flowing for all three home-grown
services with no manual span/log code yet (auto-instrumentation only).

---

## Phase 5 — Third-party app metrics on rocketman

**Goal:** observability for immich.

1. Check immich's current metrics endpoint(s) — immich exposes some Prom
   metrics via its API. Add a scrape job in the collector config.
2. Tag immich logs explicitly (`service.name=immich-server`,
   `immich-machine-learning`) via `filelog` `operators:` rules.
3. Verify in UI:
   - immich appears as a service (logs-only signal is fine).
   - Postgres + Redis metrics correlate with immich activity.

**Exit criteria:** can answer "is immich slow right now?" without SSH.

---

## Phase 6 — Dashboards, alerts, runbooks

**Goal:** make the data useful, not just present.

1. Build seed dashboards (saved to `services/signoz/dashboards/*.json`):
   - "Host overview" (CPU/mem/disk/net per host).
   - "Container fleet" (top mem/cpu, restart counts).
   - "Immich health" (DB connections, ML queue, photo ingest rate).
   - "Edge traffic" (Caddy req/s, error rate, p95 latency).
   - "Own services" (RED panels for yt-dlp/announcements/swole).
2. Configure 5–10 starter alerts (defined in SigNoz UI, exported to JSON):
   - Container in restart loop (>3 restarts in 10 min).
   - Disk usage >85% on `/mnt/storage`.
   - ClickHouse ingest lag.
   - Caddy 5xx rate >1% over 5 min.
   - Tailscale connectivity (probe rocketman→spl every minute).
3. Document each alert with a one-paragraph runbook in
   `services/signoz/RUNBOOKS.md`.
4. (Optional, later) Wire alertmanager → Discord webhook
   (`announcements` already speaks Discord — could be a relay).

**Exit criteria:** opening Grafana/SigNoz on day 1 of an incident gives you
immediately useful context.

---

## Phase 7 — Documentation & polish

1. Update top-level `README.md`:
   - Replace "Monitoring/alerting with Prometheus/Grafana" + "Centralized
     logging" in the Future Enhancements section with a link to OTEL_SPEC.md.
   - Add Observability section explaining `http://rocketman:8080` access.
   - Add troubleshooting subsection.
2. Update `SERVICES.md` with new ports (8080, 4317, 4318, 9100, 8081, etc.).
3. Update `.env.example` (already done in Phase 1, double-check).
4. Make sure `update.sh` pulls the new images.
5. Document the "where does this signal come from?" map for future you.

---

## Risk register

| Risk | Mitigation |
|---|---|
| ClickHouse OOM on rocketman | Memory limit + `max_server_memory_usage_to_ram_ratio=0.5`; alert on container restarts. |
| SPL → rocketman OTLP link flaps | Collector `sending_queue` + `retry_on_failure`; buffer to disk. |
| Submodule SDK upgrades break apps | Pin SDK versions; instrument behind feature flag (`OTEL_SDK_DISABLED=true`). |
| SigNoz upgrade migration breaks schema | Always read SigNoz upgrade notes; back up `/mnt/storage/signoz/clickhouse` before major bumps. |
| Disk fills from logs | Per-signal TTLs (SPEC §6); Docker log rotation in compose. |
| Sensitive data in logs | `attributes/redact` processor with regex for tokens/passwords; document in RUNBOOKS. |
| Tailscale outage hides telemetry | Acceptable — when Tailscale is down, the host can't reach the UI anyway; signals queue on SPL. |

---

## Estimated effort

| Phase | Effort |
|---|---|
| 0 — Prep | 1 hour |
| 1 — SigNoz stack | 4–6 hours |
| 2 — Local infra | 2–3 hours |
| 3 — SPL edge | 2–3 hours |
| 4 — App instrumentation (×3 submodules) | 4–8 hours total |
| 5 — Immich/3p | 1–2 hours |
| 6 — Dashboards/alerts | 3–5 hours |
| 7 — Docs | 1–2 hours |
| **Total** | **~18–30 hours of focused work** |

Realistic calendar: 2–3 weekends of evening sessions.

---

## What I'll ask you again, when

- **Before Phase 1**: confirm SigNoz version pin.
- **Before Phase 2**: confirm Docker log rotation settings (size/count).
- **Before Phase 4**: which submodule do you want instrumented first?
  (announcements is smallest → fastest validation; yt-dlp has the most
  interesting traces to look at; swole is unknown to me until I open it.)
- **Before Phase 6**: which alerts actually matter to you? Default list is
  starter-only.
