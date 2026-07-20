# OTel Collector Config v0.144.5 + ClickHouse Pin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the `signoz-otel-collector` crash-loop on rocketman by rewriting
`services/signoz/otel-collector-config.yaml` for the v0.144.5 schema, and bump
the committed ClickHouse default pin from `24.1.2-alpine` to `25.5.6` so fresh
clones deploy correctly.

**Architecture:** Pure config change — no application code. The collector config
is a YAML file consumed by the `signoz/signoz-otel-collector:v0.144.5` image. The
rewrite merges the official upstream v0.129.0 reference structure with the
rocketman-specific customisations (Prometheus scrape targets, filelog receiver,
memory limits, `signoz-clickhouse` DSN hostname). The ClickHouse pin is updated
in three committed files: the compose defaults, `.env.example`, and `VERSIONS.md`.

**Tech Stack:** YAML, Docker Compose, SigNoz OTel collector v0.144.5 / SigNoz
v0.129.0, ClickHouse 25.5.6.

**Context / verified state (SSH to rocketman, Jun 21 2026):**
- Repo on both this machine and rocketman is at commit `d9c6807` (clean tree
  except unrelated `services/announcements` + `services/yt-dlp` submodules).
- Host prereq fixes (deploy.sh, docker-compose.yml, generate_config.sh,
  bind-mount paths in docker-compose.signoz.yml) are **already committed**.
- `signoz-otel-collector` crash-loops with fatal:
  `'migration.MetricsConfigV030' has invalid keys: address`
- Host `.env` already has `CLICKHOUSE_VERSION=25.5.6`; committed defaults still
  say `24.1.2-alpine`.
- Reference URL (authoritative):
  `https://raw.githubusercontent.com/SigNoz/signoz/v0.129.0/deploy/docker/otel-collector-config.yaml`

---

## File Map

| File | Action | Reason |
|---|---|---|
| `services/signoz/otel-collector-config.yaml` | **Rewrite** | Drop crashed `telemetry.metrics.address`; add `signozmeter` connector, `signozclickhousemeter` + `metadataexporter` exporters, `batch/meter` processor, five-pipeline service block. |
| `services/signoz/docker-compose.signoz.yml` | **Edit** (2 lines) | Bump `CLICKHOUSE_VERSION:-24.1.2-alpine` → `:-25.5.6` (2 occurrences). |
| `.env.example` | **Edit** (1 line) | Bump `CLICKHOUSE_VERSION=24.1.2-alpine` → `25.5.6`; update comment. |
| `services/signoz/VERSIONS.md` | **Edit** (2 lines) | Bump pin cell, replace moot arm64/Pi note with v0.144.5 DDL rationale. |

---

### Task 1: Rewrite `services/signoz/otel-collector-config.yaml`

**Files:**
- Modify: `services/signoz/otel-collector-config.yaml`

The current file (`services/signoz/otel-collector-config.yaml`) has 163 lines.
The crash is at lines 144–147 (`service.telemetry.metrics.address: 0.0.0.0:8888`
— a key removed in the v0.144.5 schema). The new file merges:
- Official v0.129.0 upstream structure (fetched and verified).
- Rocketman customisations: four Prometheus scrape jobs, `filelog` receiver,
  `memory_limiter`, `resourcedetection/system`, `signozspanmetrics/delta`.
- All DSNs rewritten from `clickhouse:9000` (upstream) to `signoz-clickhouse:9000`
  (the Docker network service name on `cys-service`).

- [ ] **Step 1: Write the new config**

Replace the entire file with the content below.
(`services/signoz/otel-collector-config.yaml`)

```yaml
# SigNoz OTel Collector config (rocketman) — aligned with signoz-otel-collector v0.144.5
#
# Derived from the official SigNoz v0.129.0 reference:
#   deploy/docker/otel-collector-config.yaml
# with the following rocketman additions:
#   - prometheus receiver: scrape cadvisor, node-exporter, postgres-exporter,
#     redis-exporter via the cys-service docker network.
#   - filelog receiver: ship Docker container logs from the host bind-mount.
#   - memory_limiter processor: cap collector at 800 MiB (compose limit 1 G).
#   - resourcedetection/system: add env + host labels.
#   - signozspanmetrics/delta: derive RED metrics from trace spans.
#   - All ClickHouse DSNs use signoz-clickhouse:9000 (NOT clickhouse:9000).
#   - No service.telemetry.metrics block (removed in v0.144.5 schema).

connectors:
  signozmeter:
    metrics_flush_interval: 1h
    dimensions:
      - name: service.name
      - name: deployment.environment
      - name: host.name

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

  # ---------------------------------------------------------------------------
  # Prometheus: scrape the rocketman exporters over the cys-service docker
  # network. Targets resolve by DNS name. There is no supported config_file
  # field on the prometheus receiver — scrape_configs must be inline.
  # The skeleton services/signoz/prometheus.yml is documentation only.
  # ---------------------------------------------------------------------------
  prometheus:
    config:
      global:
        scrape_interval: 60s
      scrape_configs:
        - job_name: otel-collector
          static_configs:
            - targets:
                - localhost:8888
              labels:
                job_name: otel-collector
        - job_name: cadvisor
          scrape_interval: 15s
          static_configs:
            - targets: [cadvisor:8080]
        - job_name: node-exporter
          scrape_interval: 15s
          static_configs:
            - targets: [node-exporter:9100]
        - job_name: postgres-exporter
          scrape_interval: 15s
          static_configs:
            - targets: [postgres-exporter:9187]
        - job_name: redis-exporter
          scrape_interval: 15s
          static_configs:
            - targets: [redis-exporter:9121]

  # ---------------------------------------------------------------------------
  # filelog: ship Docker container logs. The host's /var/lib/docker/containers
  # is bind-mounted read-only (see docker-compose.signoz.yml).
  # Uses the `container` operator (format: docker) for log parsing.
  # add_metadata_from_filepath is disabled — it expects a k8s path layout.
  # A regex operator lifts the 64-hex container ID into container.id instead.
  # ---------------------------------------------------------------------------
  filelog:
    include:
      - /var/lib/docker/containers/*/*-json.log
    start_at: end
    include_file_path: true
    operators:
      - type: container
        id: container-parser
        format: docker
        add_metadata_from_filepath: false
      - type: regex_parser
        id: extract-container-id
        regex: '^/var/lib/docker/containers/(?P<container_id>[a-f0-9]{64})/'
        parse_from: attributes["log.file.path"]
        parse_to: attributes
      - type: move
        id: container-id-to-resource
        from: attributes.container_id
        to: resource["container.id"]

processors:
  batch:
    send_batch_size: 10000
    send_batch_max_size: 11000
    timeout: 10s

  batch/meter:
    send_batch_max_size: 25000
    send_batch_size: 20000
    timeout: 1s

  memory_limiter:
    check_interval: 2s
    # Keep under the 1 G compose limit for this container.
    limit_mib: 800
    spike_limit_mib: 200

  resourcedetection/system:
    # env detector adds OTEL_RESOURCE_ATTRIBUTES labels; system adds host info.
    detectors: [env, system]
    timeout: 2s

  signozspanmetrics/delta:
    metrics_exporter: signozclickhousemetrics
    metrics_flush_interval: 60s
    latency_histogram_buckets:
      [100us, 1ms, 2ms, 6ms, 10ms, 50ms, 100ms, 250ms, 500ms, 1000ms, 1400ms, 2000ms, 5s, 10s, 20s, 40s, 60s]
    dimensions_cache_size: 100000
    aggregation_temporality: AGGREGATION_TEMPORALITY_DELTA
    enable_exp_histogram: true
    dimensions:
      - name: service.namespace
        default: default
      - name: deployment.environment
        default: default
      - name: signoz.collector.id
      - name: service.version
      - name: browser.platform
      - name: browser.mobile
      - name: k8s.cluster.name
      - name: k8s.node.name
      - name: k8s.namespace.name
      - name: host.name
      - name: host.type
      - name: container.name

extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  pprof:
    endpoint: 0.0.0.0:1777

exporters:
  clickhousetraces:
    datasource: tcp://signoz-clickhouse:9000/signoz_traces
    low_cardinal_exception_grouping: ${env:LOW_CARDINAL_EXCEPTION_GROUPING}
    use_new_schema: true

  signozclickhousemetrics:
    dsn: tcp://signoz-clickhouse:9000/signoz_metrics

  clickhouselogsexporter:
    dsn: tcp://signoz-clickhouse:9000/signoz_logs
    timeout: 10s
    use_new_schema: true

  signozclickhousemeter:
    dsn: tcp://signoz-clickhouse:9000/signoz_meter
    timeout: 45s
    sending_queue:
      enabled: false

  metadataexporter:
    cache:
      provider: in_memory
    dsn: tcp://signoz-clickhouse:9000/signoz_metadata
    enabled: true
    timeout: 45s

service:
  telemetry:
    logs:
      encoding: json
  extensions:
    - health_check
    - pprof
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, signozspanmetrics/delta, resourcedetection/system, batch]
      exporters: [clickhousetraces, metadataexporter, signozmeter]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, resourcedetection/system, batch]
      exporters: [signozclickhousemetrics, metadataexporter, signozmeter]
    metrics/prometheus:
      receivers: [prometheus]
      processors: [memory_limiter, resourcedetection/system, batch]
      exporters: [signozclickhousemetrics, metadataexporter, signozmeter]
    logs:
      receivers: [otlp, filelog]
      processors: [memory_limiter, resourcedetection/system, batch]
      exporters: [clickhouselogsexporter, metadataexporter, signozmeter]
    metrics/meter:
      receivers: [signozmeter]
      processors: [batch/meter]
      exporters: [signozclickhousemeter]
```

- [ ] **Step 2: YAML sanity check**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('services/signoz/otel-collector-config.yaml')); print('YAML OK')"
grep -c 'tcp://clickhouse:9000' services/signoz/otel-collector-config.yaml
grep -c 'tcp://signoz-clickhouse:9000' services/signoz/otel-collector-config.yaml
grep -c 'telemetry' services/signoz/otel-collector-config.yaml
grep -A2 'telemetry:' services/signoz/otel-collector-config.yaml | grep -c 'address'
```

Expected:
- `YAML OK`
- `0` (no bare `clickhouse:9000`)
- `5` (exactly five `signoz-clickhouse:9000` DSNs)
- `1` (telemetry appears once — in the `service.telemetry.logs` block)
- `0` (no `address` under telemetry)

If any check fails, fix the YAML before proceeding.

---

### Task 2: Bump the ClickHouse committed pin from 24.1.2-alpine to 25.5.6

**Files:**
- Modify: `services/signoz/docker-compose.signoz.yml` (lines 34, 82)
- Modify: `.env.example` (line 153)
- Modify: `services/signoz/VERSIONS.md` (lines 11, 24–26)

The host `.env` already overrides this to `25.5.6`, but fresh clones would get
`24.1.2-alpine` which fails the v0.144.5 migrator with a code 62 DDL syntax error
(`JSON(max_dynamic_paths=100)` not understood by ClickHouse 24.x).

- [ ] **Step 1: Bump docker-compose.signoz.yml defaults**

In `services/signoz/docker-compose.signoz.yml`, change both occurrences of
`CLICKHOUSE_VERSION:-24.1.2-alpine` to `CLICKHOUSE_VERSION:-25.5.6`:

- Line 34: `image: clickhouse/clickhouse-server:${CLICKHOUSE_VERSION:-24.1.2-alpine}`
  → `image: clickhouse/clickhouse-server:${CLICKHOUSE_VERSION:-25.5.6}`
- Line 82: same change.

Verify: `grep -c '24.1.2' services/signoz/docker-compose.signoz.yml` → `0`

- [ ] **Step 2: Bump .env.example**

In `.env.example` line 153, change:
```
CLICKHOUSE_VERSION=24.1.2-alpine            # verify arm64/ARMv8.2-A support on the Pi before bumping
```
to:
```
CLICKHOUSE_VERSION=25.5.6                   # 24.1.2 too old for v0.144.5 migrator JSON(max_dynamic_paths) DDL
```

Verify: `grep 'CLICKHOUSE_VERSION' .env.example`

- [ ] **Step 3: Update VERSIONS.md pin and note**

In `services/signoz/VERSIONS.md`:

- Line 11: change `| ClickHouse | \`CLICKHOUSE_VERSION\` | \`24.1.2-alpine\` | SigNoz-recommended pin (verify arm64 on Pi) |`
  to: `| ClickHouse | \`CLICKHOUSE_VERSION\` | \`25.5.6\` | SigNoz v0.129.0 ships 25.5.6; 24.1.2 too old for v0.144.5 migrator |`

- Lines 24–26 (the ClickHouse arm64 note): replace:
  ```
  - **ClickHouse on arm64 (rocketman Pi)**: arm64 ClickHouse needs ARMv8.2-A. If the
    Pi crashes with "illegal instruction", drop to a ClickHouse tag known to work on
    the host, or move ClickHouse to an amd64 host.
  ```
  with:
  ```
  - **ClickHouse 25.5.6 required**: the signoz-otel-collector v0.144.5 schema
    migrator emits `JSON(max_dynamic_paths=100)` DDL that ClickHouse 24.x does not
    understand (fails: code 62 syntax error). Pin to 25.5.6 or later.
    rocketman is x86_64 (Intel i5-4570T) — no arm64 constraint applies.
  ```

Verify: `grep -c '24.1.2' services/signoz/VERSIONS.md` → `0`

---

### Task 3: Verify and commit

**Files:** all four files above.

- [ ] **Step 1: Final cross-check**

```bash
# No 24.1.2 anywhere in the four files:
grep -c '24.1.2' services/signoz/otel-collector-config.yaml services/signoz/docker-compose.signoz.yml .env.example services/signoz/VERSIONS.md

# Collector YAML checks (repeat from Task 1 Step 2):
python3 -c "import yaml; yaml.safe_load(open('services/signoz/otel-collector-config.yaml')); print('YAML OK')"
grep -c 'tcp://clickhouse:9000' services/signoz/otel-collector-config.yaml     # expect 0
grep -c 'tcp://signoz-clickhouse:9000' services/signoz/otel-collector-config.yaml  # expect 5
grep -A2 'telemetry:' services/signoz/otel-collector-config.yaml | grep -c 'address'  # expect 0
```

All counts must match expectations before committing.

- [ ] **Step 2: Stage only the four target files**

```bash
git add services/signoz/otel-collector-config.yaml \
        services/signoz/docker-compose.signoz.yml \
        .env.example \
        services/signoz/VERSIONS.md
git status --short
```

Confirm staged: only the four files above appear as `M`. The unrelated
`services/announcements` and `services/yt-dlp` submodule modifications must NOT
be staged.

- [ ] **Step 3: Commit**

```bash
git commit -m 'fix(otel): align collector config with v0.144.5; bump ClickHouse pin

- otel-collector-config.yaml: drop service.telemetry.metrics.address (crash fix
  for signoz-otel-collector v0.144.5); add signozmeter connector,
  signozclickhousemeter + metadataexporter exporters, batch/meter processor, and
  five-pipeline service config matching the official SigNoz v0.129.0 layout.
  Preserve rocketman prometheus scrape targets (cadvisor, node-exporter,
  postgres-exporter, redis-exporter) and filelog receiver. All DSNs use
  signoz-clickhouse:9000 (not upstream clickhouse:9000).
- docker-compose.signoz.yml, .env.example, VERSIONS.md: bump committed
  CLICKHOUSE_VERSION default 24.1.2-alpine -> 25.5.6. 24.1.2 is too old for the
  v0.144.5 migrator JSON(max_dynamic_paths=100) DDL (fails: code 62 syntax
  error). Fresh clones now deploy with the correct version.'
```

- [ ] **Step 4: Verify commit**

```bash
git log --oneline -3
git show --stat HEAD
```

Expected: new commit at top; `show --stat` lists the four files and nothing else
(no `.env`, no stray files).

---

## Host deploy (run on rocketman after pulling/copying the new config)

These steps are out of scope for this code-repo plan. They run on rocketman
(`/opt/docker/composeyourself`) after the above commit is pulled or the file is
copied to the host. See `docs/plans/OTEL_FIX_COLLECTOR_CONFIG.md` Tasks 2–3 and
5 for the full host sequence: force-recreate the collector, 90-second stability
watch, live verification (UI health, OTLP ports, log check, restart persistence),
and remove `/etc/sudoers.d/aaron-temp`.

Quick reference for the host operator:

```bash
# On rocketman — pull new config or copy from this repo:
cd /opt/docker/composeyourself
sg dockerops -c "git pull"   # or copy services/signoz/otel-collector-config.yaml manually

CF="-f docker-compose.yml -f docker-compose.rocketman.yml -f services/signoz/docker-compose.signoz.yml"
sg dockerops -c "docker compose $CF up -d --force-recreate signoz-otel-collector"
sleep 90
docker inspect -f '{{.State.Status}} restarts={{.RestartCount}}' signoz-otel-collector
docker logs signoz-otel-collector --tail 20 2>&1 | grep -iE 'fatal|error|ready|Started'
```
