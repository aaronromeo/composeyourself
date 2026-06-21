# SigNoz / OTEL Deploy — Fix Collector Config & Land the Stack (rocketman)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. This plan
> runs **on the rocketman host** (`/opt/docker/composeyourself`), inside an
> OpenCode session with shell access. You do NOT have the prior chat context —
> everything you need is below.

## Why this plan exists

A prior session (executing `OTEL_HOST_DEPLOY_ROCKETMAN.md`) got the SigNoz stack
**almost** fully up but hit a chain of bugs in the merged OTEL code. Most are
already fixed on disk (uncommitted). **One blocker remains:** the
`signoz-otel-collector` crash-loops because its config file
(`services/signoz/otel-collector-config.yaml`) targets an **older** collector
schema than the pinned image `signoz/signoz-otel-collector:v0.144.5`.

This plan: (1) fixes the collector config to match v0.144.5, (2) brings the stack
fully green, (3) verifies, and (4) commits the now-working changes.

## Ground truth about the host (corrects the original plan's assumptions)

- **rocketman is x86_64** (Intel Core i5-4570T), **NOT** an arm64 Raspberry Pi.
  All "arm64 / ARMv8.2-A / Pi" warnings in the original plan are moot.
- Repo: `/opt/docker/composeyourself`, owned by **`dockerops`** (uid 999, gid 989).
- You are likely user **`aaron`** (uid 1000). `aaron` is a member of the
  `dockerops` group but **the login session does not have that group active**, so
  direct file writes into the repo fail with "Permission denied". **Workaround:**
  wrap repo file writes in `sg dockerops -c "..."`. Example:
  `sg dockerops -c "cp /tmp/x /opt/docker/composeyourself/x"`.
- A **temporary** sudoers drop-in grants `aaron` passwordless sudo:
  `/etc/sudoers.d/aaron-temp` containing `aaron ALL=(ALL) NOPASSWD: ALL`.
  Use `sudo` freely. **This file must be removed at the end (Task 5).**
- Tailscale runs as a `network_mode: host` container named `tailscale`. The host's
  tailnet IP is **`100.109.74.20`** (`docker exec tailscale tailscale ip -4`).

## Compose invocation (used everywhere below)

```bash
cd /opt/docker/composeyourself
CF="-f docker-compose.yml -f docker-compose.rocketman.yml -f services/signoz/docker-compose.signoz.yml"
# Run compose under the dockerops group so it can read the repo:
sg dockerops -c "docker compose $CF <subcommand>"
```

## What is ALREADY fixed on disk (uncommitted — do NOT redo)

These edits are present in the working tree (`git diff` shows them). They are
correct and verified working. **Leave them; Task 4 commits them.**

1. **`deploy.sh`**: `chown -R pi:pi` → `chown -R dockerops:dockerops` (host has no
   `pi` user).
2. **`docker-compose.yml`**: added `TS_USERSPACE=false` to the `tailscale` service.
   *Why:* the container was defaulting to `--tun=userspace-networking`, so no
   `tailscale0` kernel interface existed, so Docker could not bind container ports
   to `100.109.74.20` ("cannot assign requested address"). With `TS_USERSPACE=false`
   the `tailscale0` interface appears and port binding works.
3. **`services/signoz/docker-compose.signoz.yml`**: six bind-mount sources changed
   from `./<file>` to `./services/signoz/<file>` (clickhouse-config.xml,
   clickhouse-users.xml, clickhouse-cluster.xml, clickhouse-custom-function.xml,
   otel-collector-config.yaml, alertmanager.yml).
   *Why:* compose resolves `./` relative to the **project directory (repo root)**,
   not the overlay file's dir. The files live in `services/signoz/`, so `./x`
   pointed at a non-existent repo-root path and Docker auto-created empty
   **directories** there, breaking the mounts ("is a directory" errors).
4. **`generate_config.sh`**: the Authelia block (OIDC keys, users_database.yml,
   configuration.yml) is now wrapped in `if [ -z "${OAUTH_CLIENT_SECRET}" ]; then
   skip; else ...; fi`. *Why:* rocketman does not run Authelia and has no
   `OAUTH_CLIENT_SECRET`; the old script prompted for an Authelia admin password
   (no TTY → abort) and passed an empty `--password` to `authelia crypto hash`.

### Host-only state already set (NOT in git, already done)

- `.env` has: `DOMAIN=rocketman.local` (placeholder so generate_config.sh runs),
  `SIGNOZ_BIND_ADDR=100.109.74.20`, a 64-char `SIGNOZ_JWT_SECRET`, and
  `CLICKHOUSE_VERSION=25.5.6`.
  - **`CLICKHOUSE_VERSION=25.5.6` is essential.** The compose default
    `24.1.2-alpine` is too old: the v0.144.5 schema migrator emits
    `JSON(max_dynamic_paths=100)` DDL that only ClickHouse 25.x understands
    (migrator failed on 24.1.2 with `code: 62 Syntax error`). `25.5.6` is the
    version SigNoz v0.129.0 ships officially, and it is verified healthy here.
- `/mnt/storage/signoz/{clickhouse,zookeeper,signoz,alertmanager}` exist; the
  ClickHouse/ZooKeeper/signoz data was wiped clean for the 25.5.6 reinit and
  `clickhouse/user_scripts/histogramQuantile` is preserved.

### Current container state (verified before this plan)

`signoz-clickhouse`, `signoz-zookeeper`, `signoz` (UI) → **Up (healthy)**.
`signoz-init-clickhouse`, `signoz-schema-migrator` → **Exited (0)** (correct;
one-shot). `signoz-otel-collector` → **Restarting (1)** (the remaining blocker).
The SigNoz UI already answers `http://100.109.74.20:8080/api/v1/health` →
`{"status":"ok"}`.

---

## The actual blocker: collector config schema mismatch

`docker logs signoz-otel-collector` shows:

```
'service.telemetry.metrics' decoding failed ... 'migration.MetricsConfigV030'
has invalid keys: address
```

The committed config (`services/signoz/otel-collector-config.yaml`) is a
custom-tuned file (it adds rocketman's Prometheus scrape targets + a `filelog`
receiver for Docker logs — **keep that work**) but its `service:` section and
`exporters:` list match an **older** collector. The official v0.129.0 collector
config (for the same `v0.144.5` image) differs in several required ways.

**Authoritative reference** (fetch and read it first):
`https://raw.githubusercontent.com/SigNoz/signoz/v0.129.0/deploy/docker/otel-collector-config.yaml`

Key differences the new config MUST adopt:

- **Remove** `service.telemetry.metrics.address: 0.0.0.0:8888` entirely (this is
  the immediate crash). The official config has **no** `telemetry.metrics` block.
- **Add the meter connector** `signozmeter` (top-level `connectors:` block).
- **Add exporters** present in the official config but missing here:
  `signozclickhousemeter`, `metadataexporter`. Keep existing `clickhousetraces`,
  `signozclickhousemetrics`, `clickhouselogsexporter`.
- **Update pipelines** to the official shape: `traces`, `metrics`,
  `metrics/prometheus`, `logs`, `metrics/meter`, each routing through the new
  exporters (`metadataexporter`, `signozmeter`, `signozclickhousemeter`).

**Preserve rocketman customizations** when merging:
- The `prometheus` receiver `scrape_configs` for `cadvisor:8080`,
  `node-exporter:9100`, `postgres-exporter:9187`, `redis-exporter:9121`.
- The `filelog` receiver (Docker container logs) and its operators.
- All ClickHouse DSNs must use host **`signoz-clickhouse:9000`** (the container
  name on the `cys-service` network) — the official config uses `clickhouse:9000`,
  which does NOT resolve here. Rewrite every `tcp://clickhouse:9000/...` to
  `tcp://signoz-clickhouse:9000/...`.
- Keep `memory_limiter` and `resourcedetection/system` processors (rocketman has a
  1G memory cap on the collector).

---

### Task 0: Orient and confirm the blocker

**Files:** none (read-only)

- [ ] **Step 1: Confirm repo, host, tailnet IP, group workaround**

```bash
cd /opt/docker/composeyourself
whoami
test -f services/signoz/otel-collector-config.yaml && echo "REPO OK"
docker exec tailscale tailscale ip -4 | head -n1   # expect 100.109.74.20
ip addr show tailscale0 >/dev/null 2>&1 && echo "tailscale0 UP" || echo "tailscale0 MISSING (see Task 3 note)"
sg dockerops -c "echo group-write-ok"
sudo -n true && echo "SUDO PASSWORDLESS OK"
```

- [ ] **Step 2: Confirm the collector is the only thing broken**

```bash
docker ps -a --format '{{.Names}}\t{{.Status}}' | grep -E 'signoz|clickhouse|zookeeper' | sort
docker logs signoz-otel-collector --tail 15 2>&1 | grep -iE 'invalid keys|telemetry|fatal' | tail -3
```

Expected: clickhouse/zookeeper/signoz `Up (healthy)`; migrator/init `Exited (0)`;
collector `Restarting` with the `invalid keys: address` fatal. If the error is
different, read the full log and adapt — STOP and report if it's not a config
decode error.

---

### Task 1: Rewrite the collector config for v0.144.5

**Files:**
- Modify: `services/signoz/otel-collector-config.yaml`

- [ ] **Step 1: Fetch the official reference config**

```bash
curl -sf "https://raw.githubusercontent.com/SigNoz/signoz/v0.129.0/deploy/docker/otel-collector-config.yaml" -o /tmp/official-otel.yaml && echo "FETCHED" || echo "FETCH FAILED (use the URL above via your web tool)"
```

- [ ] **Step 2: Back up the current config**

```bash
sg dockerops -c "cp -a services/signoz/otel-collector-config.yaml /tmp/otel-collector-config.bak.yaml" && echo "BACKED UP"
```

- [ ] **Step 3: Write the merged config**

Author a new `services/signoz/otel-collector-config.yaml` that takes the official
v0.129.0 structure and merges in the rocketman customizations. Write it to a temp
file then install with `sg dockerops -c "cp /tmp/new-otel.yaml services/signoz/otel-collector-config.yaml"`
(direct writes fail due to group perms).

It MUST contain:

- `connectors:` → `signozmeter:` (copy from official).
- `receivers:` → `otlp` (grpc 0.0.0.0:4317, http 0.0.0.0:4318), the rocketman
  `prometheus` block (the 4 scrape jobs listed above; you may also add the
  official `otel-collector`→`localhost:8888` self-scrape job), and the rocketman
  `filelog` block (verbatim from the backup).
- `processors:` → `batch`, `batch/meter` (from official), `memory_limiter`
  (from backup), `resourcedetection/system` (from backup), `signozspanmetrics/delta`
  (from backup; it references `metrics_exporter: signozclickhousemetrics`).
- `extensions:` → `health_check` (0.0.0.0:13133), `pprof` (0.0.0.0:1777).
- `exporters:` → `clickhousetraces`, `signozclickhousemetrics`,
  `clickhouselogsexporter`, `signozclickhousemeter`, `metadataexporter`
  — **all DSNs `tcp://signoz-clickhouse:9000/...`** (signoz_traces, signoz_metrics,
  signoz_logs, signoz_meter, signoz_metadata respectively). Keep
  `low_cardinal_exception_grouping: ${env:LOW_CARDINAL_EXCEPTION_GROUPING}` and
  `use_new_schema: true` on traces/logs.
- `service:`
  - `telemetry:` → `logs: { encoding: json }` ONLY. **No `metrics:` block.**
  - `extensions: [health_check, pprof]`
  - `pipelines:` (mirror official, but include rocketman receivers):
    - `traces`: receivers `[otlp]`, processors
      `[memory_limiter, signozspanmetrics/delta, resourcedetection/system, batch]`,
      exporters `[clickhousetraces, metadataexporter, signozmeter]`
    - `metrics`: receivers `[otlp]`, processors
      `[memory_limiter, resourcedetection/system, batch]`, exporters
      `[signozclickhousemetrics, metadataexporter, signozmeter]`
    - `metrics/prometheus`: receivers `[prometheus]`, processors
      `[memory_limiter, resourcedetection/system, batch]`, exporters
      `[signozclickhousemetrics, metadataexporter, signozmeter]`
    - `logs`: receivers `[otlp, filelog]`, processors
      `[memory_limiter, resourcedetection/system, batch]`, exporters
      `[clickhouselogsexporter, metadataexporter, signozmeter]`
    - `metrics/meter`: receivers `[signozmeter]`, processors `[batch/meter]`,
      exporters `[signozclickhousemeter]`

- [ ] **Step 4: YAML sanity check**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('services/signoz/otel-collector-config.yaml')); print('YAML OK')"
grep -c 'tcp://clickhouse:9000' services/signoz/otel-collector-config.yaml   # expect: 0
grep -c 'tcp://signoz-clickhouse:9000' services/signoz/otel-collector-config.yaml  # expect: 5
grep -c 'telemetry' services/signoz/otel-collector-config.yaml               # expect: 1 (logs only)
grep -A2 'telemetry:' services/signoz/otel-collector-config.yaml | grep -c 'address'  # expect: 0
```

Expected: `YAML OK`, no `clickhouse:9000`, five `signoz-clickhouse:9000`, no
`address` under telemetry. If any differ, fix before proceeding.

---

### Task 2: Recreate the collector and confirm it stays up

**Files:** none

- [ ] **Step 1: Force-recreate the collector**

```bash
cd /opt/docker/composeyourself
CF="-f docker-compose.yml -f docker-compose.rocketman.yml -f services/signoz/docker-compose.signoz.yml"
sg dockerops -c "docker compose $CF up -d --force-recreate signoz-otel-collector 2>&1" | tail -5
```

- [ ] **Step 2: Watch it for 90 seconds — it must NOT be Restarting**

```bash
for i in $(seq 1 6); do
  s=$(docker inspect -f '{{.State.Status}} restarts={{.RestartCount}}' signoz-otel-collector 2>/dev/null)
  echo "check $i: $s"; sleep 15
done
docker logs signoz-otel-collector --tail 30 2>&1 | grep -iE 'error|fatal|refused|invalid|Everything is ready|Started' | tail -10
```

Expected: status `running` with the restart count NOT climbing, and logs showing
the collector started (look for `Everything is ready` / pipeline start, and no
`fatal`). If it still fatals on a config key, read the exact key, compare against
`/tmp/official-otel.yaml`, fix Task 1 Step 3, and repeat. **If it cannot reach
`signoz-clickhouse:9000`**, confirm the DSNs and that `signoz-clickhouse` is
healthy (`docker ps`); transient startup warnings are fine.

---

### Task 3: Full verification (Tasks 6–7 of the original plan)

**Files:** none. `TS_IP=100.109.74.20`.

> If `ip addr show tailscale0` was MISSING in Task 0, recreate tailscale first:
> `sg dockerops -c "docker compose $CF up -d tailscale"; sleep 15;
> ip addr show tailscale0`. Then re-run any container that failed to bind.

- [ ] **Step 1: All signoz containers healthy**

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E 'signoz|clickhouse|zookeeper|node-exporter|cadvisor|exporter' | sort
```

Expected: `signoz`, `signoz-clickhouse`, `signoz-zookeeper`,
`signoz-otel-collector` all `Up` (healthy where they have healthchecks); the
exporters `Up`; `signoz-init-clickhouse` and `signoz-schema-migrator`
`Exited (0)`.

- [ ] **Step 2: UI health on the tailnet IP**

```bash
curl -sf "http://100.109.74.20:8080/api/v1/health" && echo "  <- UI HEALTH OK"
```

Expected: `{"status":"ok"}` then `UI HEALTH OK`.

- [ ] **Step 3: OTLP ingest ports open on the tailnet IP**

```bash
for p in 4317 4318; do (echo > /dev/tcp/100.109.74.20/$p) >/dev/null 2>&1 && echo "$p OPEN" || echo "$p CLOSED"; done
```

Expected: both `OPEN`.

- [ ] **Step 4: Collector is ingesting infra metrics without persistent errors**

```bash
docker logs signoz-otel-collector --tail 40 2>&1 | grep -iE 'error|refused' | tail -10 || echo "no errors (good)"
```

Expected: no repeating `connection refused` to `signoz-clickhouse:9000`. Transient
startup lines are OK.

- [ ] **Step 5: Persistence check (compose restart survives)**

```bash
cd /opt/docker/composeyourself
CF="-f docker-compose.yml -f docker-compose.rocketman.yml -f services/signoz/docker-compose.signoz.yml"
sg dockerops -c "docker compose $CF restart signoz signoz-clickhouse signoz-otel-collector"
sleep 40
curl -sf "http://100.109.74.20:8080/api/v1/health" >/dev/null && echo "UI OK AFTER RESTART"
docker inspect -f '{{.State.Status}}' signoz-otel-collector   # expect: running
```

Expected: `UI OK AFTER RESTART` and collector `running`.

---

### Task 4: Commit the working changes

**Files:** commits the 4 already-modified tracked files + the new collector config.

> Hard rules: NEVER commit `.env`, the `.env.bak.*` backups, or the
> `SIGNOZ_JWT_SECRET`. Do NOT `git push` unless the operator asks.

- [ ] **Step 1: Review what will be committed**

```bash
cd /opt/docker/composeyourself
sg dockerops -c "git status --short"
sg dockerops -c "git diff --stat -- deploy.sh docker-compose.yml generate_config.sh services/signoz/docker-compose.signoz.yml services/signoz/otel-collector-config.yaml"
```

Confirm ONLY these five files are staged below. If `git status` shows `.env`,
`.env.bak.*`, or stray root-level `clickhouse-*.xml` / `otel-collector-config.yaml`
/ `alertmanager.yml` (leftover Docker-created dirs), do NOT add them. Remove stray
root-level config dirs if present:
`sudo rm -rf clickhouse-*.xml otel-collector-config.yaml alertmanager.yml`
(only if they are at the **repo root**, not under `services/signoz/`).

- [ ] **Step 2: Stage and commit**

```bash
sg dockerops -c "git add deploy.sh docker-compose.yml generate_config.sh services/signoz/docker-compose.signoz.yml services/signoz/otel-collector-config.yaml"
sg dockerops -c "git commit -m 'fix(otel): land SigNoz stack on rocketman (x86_64)

- collector config: align with signoz-otel-collector v0.144.5 (drop
  service.telemetry.metrics.address; add signozmeter connector,
  signozclickhousemeter + metadataexporter; new pipelines). Keep rocketman
  prometheus scrape + filelog receiver. DSNs use signoz-clickhouse:9000.
- compose: fix six config bind-mount paths (./ -> ./services/signoz/) so they
  resolve against the project dir (repo root) instead of creating empty dirs.
- tailscale: TS_USERSPACE=false so tailscale0 kernel iface exists and Docker can
  bind container ports to the tailnet IP.
- generate_config.sh: skip Authelia block when OAUTH_CLIENT_SECRET unset
  (rocketman runs no Authelia).
- deploy.sh: chown media to dockerops (host has no pi user).'"
sg dockerops -c "git log --oneline -1"
```

- [ ] **Step 3: Also bump the ClickHouse pin in committed templates (so a fresh
  clone deploys correctly)**

The working `CLICKHOUSE_VERSION=25.5.6` currently lives only in the host `.env`.
Update the committed default + docs so future deploys don't regress to 24.1.2:

```bash
cd /opt/docker/composeyourself
# Update the compose default(s):
grep -rn 'CLICKHOUSE_VERSION:-24.1.2-alpine' services/signoz/docker-compose.signoz.yml
sg dockerops -c "sed -i 's/CLICKHOUSE_VERSION:-24.1.2-alpine/CLICKHOUSE_VERSION:-25.5.6/g' services/signoz/docker-compose.signoz.yml"
# Update VERSIONS.md and .env.example if they mention 24.1.2:
grep -rln '24.1.2' .env.example services/signoz/VERSIONS.md 2>/dev/null
```

For each file that mentions `24.1.2`, change the pin to `25.5.6` and (in
`VERSIONS.md`) note: "SigNoz v0.129.0 ships ClickHouse 25.5.6; 24.1.2 is too old
for the v0.144.5 migrator's JSON(max_dynamic_paths) DDL." Then amend the commit:

```bash
sg dockerops -c "git add services/signoz/docker-compose.signoz.yml .env.example services/signoz/VERSIONS.md"
sg dockerops -c "git commit --amend --no-edit"
sg dockerops -c "git show --stat HEAD | head -20"
```

(If a file doesn't mention 24.1.2, skip it — don't force an edit.)

---

### Task 5: Remove the temporary sudo grant

**Files:** removes `/etc/sudoers.d/aaron-temp`.

- [ ] **Step 1: Remove the temp sudoers file and validate**

```bash
sudo rm -f /etc/sudoers.d/aaron-temp
sudo visudo -c
sudo -n true 2>/dev/null && echo "WARN: aaron still has passwordless sudo (unexpected)" || echo "temp sudo removed (expected)"
```

Expected: `visudo` reports `parsed OK`, and the final line confirms the temp grant
is gone.

> Note: `/etc/sudoers.d/dockerops` reports "bad permissions, should be mode 0440"
> in `visudo -c`. That is **pre-existing** and out of scope — do not touch it
> unless the operator asks. (If asked: `sudo chmod 0440 /etc/sudoers.d/dockerops`.)

- [ ] **Step 2: Report final status to the operator**

```bash
echo "SigNoz UI:  http://100.109.74.20:8080  (also http://rocketman:8080 if MagicDNS)"
echo "Create the first admin user on the initial UI visit."
echo "Committed: working OTEL stack. NOT pushed (operator decision)."
```

---

## Troubleshooting

- **Collector fatal `invalid keys: <key>`** → that key was removed/renamed in
  v0.144.5. Diff your config's `service:` block against `/tmp/official-otel.yaml`
  and match the official shape exactly. The most common offender is
  `service.telemetry.metrics`.
- **Collector `connection refused` to `signoz-clickhouse:9000`** → ensure
  `signoz-clickhouse` is `Up (healthy)` and every DSN uses `signoz-clickhouse`
  (NOT `clickhouse`). The collector `migrate sync check` in its command also needs
  ClickHouse reachable.
- **`cannot assign requested address` on a port bind** → `tailscale0` interface is
  missing. Confirm `docker-compose.yml` has `TS_USERSPACE=false`, recreate the
  `tailscale` container, wait ~15s for `ip addr show tailscale0`, then re-up.
- **`... is a directory` on a config mount** → a `./x` path resolved to repo root
  and Docker made an empty dir. Confirm the mount uses `./services/signoz/x` and
  delete the stray repo-root dir (`sudo rm -rf <repo-root>/x`), then re-up.
- **Schema migrator `code: 62 Syntax error ... JSON(max_dynamic_paths`** →
  ClickHouse too old. Ensure `.env` has `CLICKHOUSE_VERSION=25.5.6` (and the
  committed default after Task 4 Step 3).
- **Repo file write "Permission denied"** → you forgot `sg dockerops -c "..."`.
- **git "dubious ownership"** when running git under `sudo`/root → run git via
  `sg dockerops -c "git ..."` instead (the working tree is `dockerops`-owned).

## Hard rules

- Never commit `.env`, `.env.bak.*`, or print `SIGNOZ_JWT_SECRET`.
- Never bind SigNoz ports to `0.0.0.0`; they must carry `SIGNOZ_BIND_ADDR`
  (`100.109.74.20`). yt-dlp legitimately keeps `0.0.0.0:8080` — that's a different
  service and is expected.
- Never `git push` unless the operator explicitly asks.
- Remove `/etc/sudoers.d/aaron-temp` before finishing (Task 5).
- If a step's expected output doesn't match, STOP and report rather than guessing.

## Out of scope

- sweetpaintedlady edge collector; Phases 4–7 (app SDK instrumentation, dashboards,
  alerts, docs); the pre-existing `/etc/sudoers.d/dockerops` permission warning.
