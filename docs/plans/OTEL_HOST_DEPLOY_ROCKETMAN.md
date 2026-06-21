# SigNoz / OTEL Host Deployment on rocketman — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. This plan runs **on the rocketman host itself** (a Raspberry Pi,
> arm64), inside an OpenCode session on that machine. You have shell access to
> the host. You do NOT have the prior chat context — everything you need is below.

**Goal:** Configure the two required environment variables on rocketman, deploy
the already-merged SigNoz observability stack, and verify the SigNoz UI loads
over Tailscale at `http://<rocketman-tailnet-ip>:8080`.

**Architecture:** This repo (`composeyourself`, deployed from a working copy on
rocketman) runs docker-compose with per-host overlays. Phases 0–3 of an
OpenTelemetry rollout were already implemented and merged to `main`: a SigNoz
backend stack (ClickHouse + ZooKeeper + collector + consolidated `signoz` UI on
port 8080) plus container/host metrics exporters. The stack is gated behind two
env vars that MUST be set on the host before deploy:
- `SIGNOZ_BIND_ADDR` — the host port to bind the SigNoz UI (`:8080`) and OTLP
  ingest (`:4317`/`:4318`) to. **Must be rocketman's Tailscale IP**, because the
  default `0.0.0.0` (a) exposes telemetry ingest on the public/LAN interface and
  (b) collides with the `yt-dlp` container which already binds host `:8080`.
- `SIGNOZ_JWT_SECRET` — SigNoz token-signing secret. The compose file falls back
  to the insecure literal `secret` if this is empty.

**Tech Stack:** docker / docker compose, Tailscale (already running as a
`network_mode: host` container named `tailscale`), bash. Host is arm64 Linux
(Raspberry Pi). The repo lives at **`/opt/docker/composeyourself`** and Docker is
run as the user **`dockerops`**. Run all commands in this plan as `dockerops`
(or a user in the `docker` group); `dockerops` must own the working copy and be
able to invoke `sudo` for the data-dir setup steps in `deploy.sh`.

---

## Background context you need (read once)

**Repo layout on the host:** The working copy is a normal git clone of
`git@github.com:aaronromeo/composeyourself.git`, located at
**`/opt/docker/composeyourself`** and owned by **`dockerops`**. Confirm it in
Task 0 before doing anything. Inside it:
- `docker-compose.yml` — base (tailscale only).
- `docker-compose.rocketman.yml` — rocketman services: yt-dlp, announcements,
  swole, immich (server/ML/redis/postgres), **and the Phase 2 exporters**
  (cadvisor, node-exporter, postgres-exporter, redis-exporter).
- `services/signoz/docker-compose.signoz.yml` — the SigNoz backend overlay.
- `deploy.sh rocketman` — brings everything up. It appends the signoz overlay
  automatically on rocketman, creates the SigNoz data dirs under
  `/mnt/storage/signoz`, runs `generate_config.sh`, then does
  `docker compose ... down`, `build --no-cache`, `up -d`.
- `.env` — host secrets file (already exists on rocketman from prior immich /
  yt-dlp deploys; NOT in git). You will append the two new vars to it.
- `.env.example` — committed template; shows the full observability block.

**How the two vars are consumed (so you understand what you're setting):**
In `services/signoz/docker-compose.signoz.yml`:
- `signoz` service: `ports: ["${SIGNOZ_BIND_ADDR:-0.0.0.0}:8080:8080"]`
- `signoz-otel-collector` service:
  `ports: ["${SIGNOZ_BIND_ADDR:-0.0.0.0}:4317:4317", "${SIGNOZ_BIND_ADDR:-0.0.0.0}:4318:4318"]`
- `signoz` service env: `SIGNOZ_TOKENIZER_JWT_SECRET=${SIGNOZ_JWT_SECRET:-secret}`

**KNOWN PRECONDITION HAZARD — `DOMAIN`:** `deploy.sh` calls
`generate_config.sh`, which **exits with an error if `DOMAIN` is not set in
`.env`**. `DOMAIN` is normally a *sweetpaintedlady* variable. If rocketman's
`.env` has no `DOMAIN`, `deploy.sh` will abort before starting any containers.
Task 2 handles this explicitly. Do not skip it.

**Tailscale IP retrieval:** The tailscale daemon runs inside a host-network
container named `tailscale`. Get rocketman's tailnet IPv4 with:
`docker exec tailscale tailscale ip -4`
(falls back to host-installed `tailscale ip -4` if the binary is on the host).

**What "done" looks like:** `docker compose ... ps` shows the signoz containers
healthy, and `curl -sf http://<tailnet-ip>:8080` (or `:8080/api/v1/health`)
succeeds. First-run SigNoz creates an admin user via the UI (manual, optional).

**If anything blocks you:** STOP and report the exact command + output. Do not
guess at secrets, do not bind to `0.0.0.0`, do not `git push`, do not modify
files outside `.env` unless a task says so.

---

### Task 0: Locate the repo and confirm host state

**Files:** none (read-only investigation)

- [ ] **Step 1: Confirm the working copy and run as the right user**

The repo lives at `/opt/docker/composeyourself` and Docker runs as `dockerops`.
Run:

```bash
whoami   # expect: dockerops (or a user in the `docker` group)
export REPO=/opt/docker/composeyourself
test -f "$REPO/docker-compose.rocketman.yml" && echo "REPO OK: $REPO"
```

Expected: `REPO OK: /opt/docker/composeyourself`. If `whoami` is not `dockerops`,
switch users first (e.g. `sudo -iu dockerops`) and re-run this plan as `dockerops`
— it must own the working copy and be able to `docker` + `sudo`.

If the path test fails, fall back to locating it (then set `REPO` accordingly):

```bash
ls -d /opt/docker/composeyourself 2>/dev/null \
  || find /opt /home -maxdepth 4 -name docker-compose.rocketman.yml 2>/dev/null
```

If still not found: STOP and report — the repo must be cloned to
`/opt/docker/composeyourself` first (out of scope for this plan; ask the human).

- [ ] **Step 2: Confirm git remote and current branch**

Run:

```bash
cd "$REPO"
git remote -v
git rev-parse --abbrev-ref HEAD
git status --short
```

Expected: remote `origin` is `aaronromeo/composeyourself`. Note the current
branch and whether the tree is dirty. If the tree has uncommitted changes you
did not make, STOP and report them (do not discard host-local changes blindly).

- [ ] **Step 3: Confirm tailscale container is up**

Run:

```bash
docker ps --filter name=tailscale --format '{{.Names}} {{.Status}}'
```

Expected: a line like `tailscale Up ...`. If absent, STOP and report — the host
isn't on the tailnet and the deploy target IP can't be derived.

---

### Task 1: Get the deployment code onto the host (merge to main, then pull)

**Files:** none (git operations on the host working copy)

**Context:** Per the agreed handoff, the OTEL work (PR #2,
`feat/otel-observability` → `main`) is merged to `main` and the host deploys
from `main`. If the PR is NOT yet merged when you run this, STOP and report; the
merge is a human decision, not something to force here.

- [ ] **Step 1: Fetch latest**

Run:

```bash
cd "$REPO"
git fetch origin
```

Expected: fetches without error.

- [ ] **Step 2: Verify the OTEL code is on origin/main**

Run:

```bash
git ls-tree -r --name-only origin/main | grep -E 'services/signoz/docker-compose.signoz.yml'
```

Expected: prints `services/signoz/docker-compose.signoz.yml`.
If it prints nothing: the PR is not merged yet. STOP and report:
"PR #2 not merged to main; cannot deploy from main."

- [ ] **Step 3: Check out and fast-forward main**

Run:

```bash
git checkout main
git pull --ff-only origin main
```

Expected: `main` updated to include the signoz overlay. If `--ff-only` fails
(host main has diverged), STOP and report the divergence — do not merge/rebase
host-local commits without human review.

- [ ] **Step 4: Update submodules (deploy.sh expects this, harmless to predo)**

Run:

```bash
git submodule update --init --recursive
```

Expected: completes without error.

- [ ] **Step 5: Confirm the signoz overlay file is present locally**

Run:

```bash
test -f services/signoz/docker-compose.signoz.yml && echo PRESENT
```

Expected: `PRESENT`.

---

### Task 2: Ensure `.env` exists and won't break generate_config.sh

**Files:**
- Modify: `$REPO/.env` (host-only, not in git)

**Context:** `deploy.sh` → `generate_config.sh` aborts if `DOMAIN` is unset.
This task makes the deploy safe without touching sweetpaintedlady concerns.

- [ ] **Step 1: Confirm .env exists**

Run:

```bash
cd "$REPO"
test -f .env && echo "ENV PRESENT" || echo "ENV MISSING"
```

If `ENV MISSING`: STOP and report. rocketman should already have a populated
`.env` from prior deploys; a missing one means prior immich/yt-dlp secrets are
absent and creating one is out of scope (needs human-held secrets).

- [ ] **Step 2: Back up .env before editing**

Run:

```bash
cp -a .env ".env.bak.$(date +%Y%m%d-%H%M%S)"
ls -la .env.bak.*
```

Expected: a timestamped backup exists.

- [ ] **Step 3: Check whether DOMAIN is set**

Run:

```bash
grep -E '^DOMAIN=' .env && echo "DOMAIN SET" || echo "DOMAIN UNSET"
```

- [ ] **Step 4: If DOMAIN is UNSET, add a placeholder so generate_config.sh passes**

Only if Step 3 printed `DOMAIN UNSET`, run:

```bash
printf '\n# Placeholder so generate_config.sh (Authelia template) does not abort\n# on rocketman. rocketman does not run Caddy/Authelia; value is unused here.\nDOMAIN=rocketman.local\n' >> .env
grep -E '^DOMAIN=' .env
```

Expected: `DOMAIN=rocketman.local` present. (If `DOMAIN` was already SET, skip
this step entirely — do not overwrite it.)

---

### Task 3: Derive the Tailscale IP and set the two observability vars

**Files:**
- Modify: `$REPO/.env`

- [ ] **Step 1: Get rocketman's Tailscale IPv4**

Run:

```bash
cd "$REPO"
TS_IP="$(docker exec tailscale tailscale ip -4 2>/dev/null | head -n1)"
[ -z "$TS_IP" ] && TS_IP="$(tailscale ip -4 2>/dev/null | head -n1)"
echo "TS_IP=$TS_IP"
```

Expected: a `100.x.y.z` address. If empty, STOP and report — cannot bind to the
tailnet without it (do NOT fall back to `0.0.0.0`).

- [ ] **Step 2: Sanity-check the IP shape**

Run:

```bash
echo "$TS_IP" | grep -Eq '^100\.[0-9]+\.[0-9]+\.[0-9]+$' && echo "IP OK" || echo "IP SUSPECT"
```

Expected: `IP OK`. If `IP SUSPECT`, STOP and report the value — Tailscale CGNAT
range is `100.64.0.0/10`; an address outside it suggests the wrong interface.

- [ ] **Step 3: Generate a strong JWT secret**

Run:

```bash
JWT="$(openssl rand -hex 32)"
echo "JWT length: ${#JWT}"
```

Expected: `JWT length: 64`.

- [ ] **Step 4: Remove any prior SIGNOZ_BIND_ADDR / SIGNOZ_JWT_SECRET lines (idempotency)**

Run:

```bash
sed -i.sedbak -E '/^SIGNOZ_BIND_ADDR=/d; /^SIGNOZ_JWT_SECRET=/d' .env
rm -f .env.sedbak
```

Expected: no error. (This makes re-runs safe; the timestamped backup from Task 2
still holds the original.)

- [ ] **Step 5: Append the two required vars with the derived values**

Run:

```bash
{
  echo ""
  echo "# --- OpenTelemetry / SigNoz (set on host $(hostname) $(date -u +%FT%TZ)) ---"
  echo "SIGNOZ_BIND_ADDR=$TS_IP"
  echo "SIGNOZ_JWT_SECRET=$JWT"
} >> .env
```

Expected: no output (success).

- [ ] **Step 6: Verify the two vars are set correctly (mask the secret)**

Run:

```bash
grep -E '^SIGNOZ_BIND_ADDR=' .env
grep -Ec '^SIGNOZ_JWT_SECRET=.{64}$' .env   # expect: 1
```

Expected: `SIGNOZ_BIND_ADDR=100.x.y.z` and the count `1` (64-char secret
present). Do NOT print the secret value itself.

- [ ] **Step 7: Confirm no other required signoz vars are missing**

The compose defaults cover image pins, but confirm `.env.example` has nothing
else mandatory that lacks a default. Run:

```bash
grep -E '^(SIGNOZ_DATA_LOCATION|ROCKETMAN_TAILSCALE_HOST)=' .env || true
```

Expected: these may be absent — they have safe compose/script defaults
(`/mnt/storage/signoz`, `rocketman`). No action needed unless you want to pin
`SIGNOZ_DATA_LOCATION`; the default is fine. (Informational step.)

---

### Task 4: Pre-flight the compose config (no containers started)

**Files:** none

**Context:** `docker compose config` renders the merged compose with `.env`
interpolation and fails loudly on bad references — a cheap check before the
expensive `build --no-cache`.

- [ ] **Step 1: Render the full merged config**

Run:

```bash
cd "$REPO"
docker compose \
  -f docker-compose.yml \
  -f docker-compose.rocketman.yml \
  -f services/signoz/docker-compose.signoz.yml \
  config > /tmp/otel-rendered.yml && echo "CONFIG OK"
```

Expected: `CONFIG OK`. If it errors, STOP and report the error (likely a missing
env var or YAML issue).

- [ ] **Step 2: Confirm the bind address resolved to the tailnet IP, not 0.0.0.0**

`docker compose config` renders ports in one of two formats depending on the
compose version: the long form (`host_ip: <ip>` + `published: "8080"`) or the
short string form (`<ip>:8080:8080`). This check covers both: it simply asserts
the tailnet IP appears next to the relevant ports and that `0.0.0.0` does not.

Run:

```bash
echo "--- lines mentioning TS_IP ---"
grep -nF "$TS_IP" /tmp/otel-rendered.yml | head
echo "--- TS_IP occurrences (expect >= 3: 8080, 4317, 4318) ---"
grep -cF "$TS_IP" /tmp/otel-rendered.yml
echo "--- 0.0.0.0 near signoz ports (expect NONE for 4317/4318/8080 under signoz) ---"
grep -nE '0\.0\.0\.0.*(4317|4318)|(4317|4318).*0\.0\.0\.0' /tmp/otel-rendered.yml || echo "none (good)"
```

Expected: the tailnet IP appears at least 3 times (UI 8080 + OTLP 4317 + 4318),
and the `0.0.0.0` check prints `none (good)`. If `4317`/`4318` show `0.0.0.0`,
STOP — `SIGNOZ_BIND_ADDR` did not propagate; re-check Task 3 Step 6.
(Note: yt-dlp legitimately keeps `0.0.0.0:8080`; that is a different service and
is expected. Only the signoz/collector ports must carry the tailnet IP.)

- [ ] **Step 3: Confirm the JWT secret is not the literal default**

The rendered value may appear as `SIGNOZ_TOKENIZER_JWT_SECRET=secret` (env-list
form) or `SIGNOZ_TOKENIZER_JWT_SECRET: secret` (mapping form). Match both:

```bash
grep -cE 'SIGNOZ_TOKENIZER_JWT_SECRET[=:][[:space:]]*secret[[:space:]]*$' /tmp/otel-rendered.yml   # expect: 0
```

Expected: `0` (the rendered value is your real 64-char secret, not `secret`).
If it prints `1`, STOP — `SIGNOZ_JWT_SECRET` did not propagate; re-check Task 3.

- [ ] **Step 4: Confirm the :8080 collision is resolved**

Both `yt-dlp` (`0.0.0.0:8080`) and `signoz` (`<TS_IP>:8080`) are present; because
they bind different host IPs, docker allows it. Step 2 already confirmed the
tailnet IP carries the signoz `8080` mapping, so this step is just a final
explicit assertion that exactly one `8080` mapping uses the tailnet IP:

```bash
grep -cF "$TS_IP" /tmp/otel-rendered.yml | grep -q '^0$' && echo "FAIL: TS_IP absent" || echo "TS_IP present (good)"
```

Expected: `TS_IP present (good)`. If `FAIL`, STOP and re-check Task 3 Step 6.

---

### Task 5: Deploy the stack

**Files:** none (runs `./deploy.sh rocketman`)

**Context:** `deploy.sh rocketman` does: submodule update, create
`/mnt/storage/signoz/{clickhouse/user_scripts,zookeeper,signoz,alertmanager}`
(chown 1000:1000), run `generate_config.sh`, then `docker compose ... down`,
`build --no-cache`, `up -d`, `ps`. The `down` will briefly stop immich/yt-dlp/etc
too — this is expected and they come back up. ClickHouse + the schema migrator
take a few minutes on a Pi; be patient.

> **Note for the `dockerops` host:** `deploy.sh` runs `sudo chown -R pi:pi
> /mnt/storage/media` (a pre-existing immich line). If this host has no `pi`
> user/group, that command will fail and abort the deploy (`set -e`). If Step 1
> aborts at `chown ... pi:pi`, STOP and report — do not edit `deploy.sh` here;
> the human decides whether to create a `pi` user or adjust that line. The SigNoz
> data dirs use numeric `chown 1000:1000`, which is user-agnostic and fine.

- [ ] **Step 1: Run the deploy**

Run (from `$REPO`):

```bash
./deploy.sh rocketman 2>&1 | tee /tmp/otel-deploy.log
```

Expected: ends with the deployment-complete banner and a `docker compose ps`
table. If it aborts at "generate_config" with a `DOMAIN` error, return to Task 2
Step 4. If a `build` fails, capture the failing service and STOP/report.

- [ ] **Step 2: Wait for the schema migrator to finish**

The `signoz-schema-migrator` is a one-shot container. Run:

```bash
cd "$REPO"
CF="-f docker-compose.yml -f docker-compose.rocketman.yml -f services/signoz/docker-compose.signoz.yml"
for i in $(seq 1 30); do
  state=$(docker inspect -f '{{.State.Status}}:{{.State.ExitCode}}' signoz-schema-migrator 2>/dev/null || echo "missing")
  echo "attempt $i: $state"
  case "$state" in
    exited:0) echo "MIGRATOR OK"; break ;;
    exited:*) echo "MIGRATOR FAILED"; docker logs --tail 50 signoz-schema-migrator; break ;;
  esac
  sleep 20
done
```

Expected: `MIGRATOR OK` within ~10 minutes. If `MIGRATOR FAILED`, STOP and
report the logs (common cause on a Pi: ClickHouse arm64 "illegal instruction" —
see Troubleshooting).

- [ ] **Step 3: Check all signoz containers are running/healthy**

Run:

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E 'signoz|clickhouse|zookeeper'
```

Expected: `signoz`, `signoz-clickhouse`, `signoz-zookeeper`,
`signoz-otel-collector` all `Up` (clickhouse/signoz should reach `(healthy)`
after their start_period). The one-shot `signoz-init-clickhouse` and
`signoz-schema-migrator` will show `Exited (0)` — that is correct.

---

### Task 6: Verify the SigNoz UI and ingest are reachable over Tailscale

**Files:** none

- [ ] **Step 1: Health-check the UI on the tailnet IP**

Run:

```bash
curl -sf "http://$TS_IP:8080/api/v1/health" && echo "  <- UI HEALTH OK"
```

Expected: a small JSON/200 response then `UI HEALTH OK`. If it fails, try
`curl -sf "http://$TS_IP:8080/"` (some versions don't expose `/api/v1/health`);
a 200 / HTML body is also success. If connection refused, check `docker logs
signoz --tail 50` and Task 5 Step 3.

- [ ] **Step 2: Confirm UI is NOT reachable on a non-tailnet interface**

Run (should FAIL to connect, proving the bind is tailnet-only):

```bash
curl -s -m 3 "http://127.0.0.1:8080/" >/dev/null && echo "REACHABLE ON LOCALHOST (unexpected)" || echo "NOT on localhost (expected)"
```

Expected: `NOT on localhost (expected)` — because `8080` is bound to the tailnet
IP, not `0.0.0.0`/loopback. (yt-dlp still owns localhost:8080; if you get a
response it's yt-dlp's, not SigNoz's — that's fine, it just means you can't
distinguish here. The Step-1 tailnet check is the authoritative one.)

- [ ] **Step 3: Confirm OTLP gRPC ingest port is open on the tailnet IP**

Run:

```bash
(echo > /dev/tcp/$TS_IP/4317) >/dev/null 2>&1 && echo "4317 OPEN" || echo "4317 CLOSED"
```

Expected: `4317 OPEN`. (A bare TCP connect is enough; gRPC handshake errors are
fine — we only prove reachability.)

- [ ] **Step 4: Confirm the collector is receiving local infra metrics**

Run:

```bash
docker logs signoz-otel-collector --tail 30 2>&1 | grep -Ei 'error|refused' | head
```

Expected: no repeating connection errors to clickhouse. Transient startup
warnings are OK. If you see persistent `connection refused` to
`signoz-clickhouse:9000`, ClickHouse may still be starting — recheck in a minute.

- [ ] **Step 5: Report access instructions to the human**

Print for the operator:

```bash
echo "SigNoz UI:  http://$TS_IP:8080   (also http://rocketman:8080 if MagicDNS is enabled)"
echo "Create the first admin user on initial UI visit."
```

This is the success state. First-admin-user creation is a manual UI step and is
optional for this plan's completion.

---

### Task 7: Persistence sanity check (optional but recommended)

**Files:** none

**Context:** Acceptance criterion: ClickHouse data survives a compose
down/up cycle. This is optional because it briefly restarts services.

- [ ] **Step 1: Confirm data dir is populated on disk**

Run:

```bash
sudo du -sh /mnt/storage/signoz/clickhouse 2>/dev/null
ls /mnt/storage/signoz/clickhouse/user_scripts/ 2>/dev/null
```

Expected: a non-trivial size and a `histogramQuantile` file in `user_scripts`.

- [ ] **Step 2: (Optional) restart only the signoz stack and re-verify**

Run:

```bash
cd "$REPO"
CF="-f docker-compose.yml -f docker-compose.rocketman.yml -f services/signoz/docker-compose.signoz.yml"
docker compose $CF restart signoz signoz-clickhouse signoz-otel-collector
sleep 30
curl -sf "http://$TS_IP:8080/api/v1/health" >/dev/null && echo "UI OK AFTER RESTART"
```

Expected: `UI OK AFTER RESTART`. If so, persistence + restart resilience are
confirmed.

---

## Troubleshooting (read if a task fails)

- **`generate_config.sh: Error: DOMAIN ... not set`** → Task 2 Step 4 wasn't run
  or `DOMAIN` line is malformed. Add `DOMAIN=rocketman.local` to `.env`.

- **Port 8080 "address already in use" during `up -d`** → `SIGNOZ_BIND_ADDR`
  didn't propagate, so SigNoz tried `0.0.0.0:8080` against yt-dlp. Re-check Task 3
  Step 6 and Task 4 Step 2; confirm `.env` has `SIGNOZ_BIND_ADDR=100.x.y.z`.

- **ClickHouse container crash-loops with "illegal instruction" /
  immediate exit** → arm64 ClickHouse needs an ARMv8.2-A CPU; some Pi 4 silicon
  lacks it. STOP and report; the fix is pinning `CLICKHOUSE_VERSION` to a tag
  known-good on this Pi or relocating ClickHouse to an amd64 host. This is a
  hardware-compat decision for the human, not something to brute-force.

- **`signoz-schema-migrator` exits non-zero** → `docker logs
  signoz-schema-migrator`. If it can't reach `signoz-clickhouse:9000`, ClickHouse
  isn't healthy yet — `docker logs signoz-clickhouse --tail 50`. The collector
  gates on the migrator (`migrate sync check`), so the whole stack waits on this.

- **UI health check refused but containers Up** → the `signoz` image takes a
  while to initialize its SQLite store + first migrations; wait for its
  healthcheck `start_period` (60s) plus a margin, then retry Task 6 Step 1.

- **Cannot reach `$TS_IP:8080` from another tailnet device** → confirm Tailscale
  ACLs permit the device, and that `tailscale status` shows rocketman online.
  Connectivity from rocketman itself (Task 6) is the in-scope check.

## Hard rules for this session

- Never set `SIGNOZ_BIND_ADDR=0.0.0.0`. If the tailnet IP can't be derived, STOP.
- Never print or commit the `SIGNOZ_JWT_SECRET` value.
- Never `git push`, never commit `.env`, never modify tracked files (this plan
  only edits the untracked host `.env`).
- Keep the `.env` backup from Task 2 until the operator confirms success.
- If a step's expected output doesn't match, STOP and report rather than
  improvising.

## What is explicitly OUT OF SCOPE here

- The sweetpaintedlady edge collector (separate host; deploy after rocketman is
  green so it has a target).
- Phases 4–7: app SDK instrumentation, immich metrics, dashboards, alerts, docs.
- Merging PR #2 (a human decision; this plan assumes it is already on `main`).
