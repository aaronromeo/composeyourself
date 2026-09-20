# Service Index Research

## Question

We have services spread across two hosts with different reachability patterns (public HTTPS, Tailscale-only, localhost-only, bind-address-specific). A static Markdown file is stale by definition. What's the right approach for a single bookmarkable index?

---

## Grounding in this repo: services and reachability

Source of truth: `docker-compose.yml` (base) + `docker-compose.rocketman.yml` + `docker-compose.sweetpaintedlady.yml` + `services/signoz/docker-compose.signoz.yml`. Every service, port, and reachability constraint below is verified against these four files.

### Rocketman (Lenovo desktop, via Tailscale)

| Service | Host binding | How to reach | Notes |
|---|---|---|---|
| **yt-dlp** | `0.0.0.0:8082` | `http://rocketman:8082` | Container port 8080 → host 8082 |
| **announcements** | `${TAILNET_BIND_ADDR:-127.0.0.1}:8091` | `http://rocketman:8091` | Tailnet IP only in prod; `depends_on: tailscale healthy` |
| **swole** | `${TAILNET_BIND_ADDR:-127.0.0.1}:8090` | `http://rocketman:8090` | Tailnet IP only; `depends_on: tailscale healthy` |
| **immich** | `0.0.0.0:2283` | `http://rocketman:2283` | Full Immich stack (server + ML + redis + postgres) |
| **cadvisor** | `127.0.0.1:8081` | Localhost only | Scrapped by SigNoz collector internally at `cadvisor:8080` |
| **node-exporter** | `${SIGNOZ_BIND_ADDR:-0.0.0.0}:9100` | Tailnet IP in prod | `depends_on: tailscale healthy` |
| **postgres-exporter** | internal (no host port) | Not directly reachable | Scraped at `postgres-exporter:9187` |
| **redis-exporter** | internal (no host port) | Not directly reachable | Scraped at `redis-exporter:9121` |
| **SigNoz UI** | `${SIGNOZ_BIND_ADDR:-0.0.0.0}:8080` | Tailnet IP in prod | Consolidated image (query-service + web UI + alertmanager on container :8080) |
| **SigNoz OTLP gRPC** | `${SIGNOZ_BIND_ADDR}:4317` | Tailnet IP | Ingest from SPL edge collector |
| **SigNoz OTLP HTTP** | `${SIGNOZ_BIND_ADDR}:4318` | Tailnet IP | Ingest from SPL edge collector |
| **SigNoz collector telemetry** | `127.0.0.1:8888` | Localhost only | |

Internal-only (no UI): signoz-clickhouse, signoz-zookeeper, signoz-init-clickhouse, signoz-schema-migrator, immich-machine-learning, immich_redis, immich_postgres.

### Sweetpaintedlady (Hetzner VPS, public + Tailscale)

| Service | Host binding | How to reach | Notes |
|---|---|---|---|
| **Open WebUI** | internal (expose :8080) | `https://${SUBDOMAIN}.${DOMAIN}` | Behind Caddy + Authelia MFA |
| **SearXNG** | internal (expose :8080) | Not directly reachable | Used by OpenWebUI at `http://searxng:8080` |
| **Authelia portal** | internal (expose :9091) | `https://auth.${DOMAIN}` | Via Caddy reverse proxy |
| **Google Workspace MCP** | internal (expose :8000) | OAuth callback only at `https://workspace-mcp.${DOMAIN}/oauth2callback` | `/mcp` deliberately NOT proxied |
| **Caddy** | `0.0.0.0:80`, `0.0.0.0:443` (TCP + UDP) | `https://${DOMAIN}` | Reverse proxy, auto HTTPS |
| **otelcol-agent** | internal (no host port) | Not directly reachable | Forwards to rocketman over Tailscale |
| **cadvisor** | internal (no host port) | Not directly reachable | Scrapped by edge collector |
| **node-exporter** | internal (no host port) | Not directly reachable | Scrapped by edge collector |

### Reachability summary

- **6 user-facing UIs** across both hosts: yt-dlp, announcements, swole, immich, SigNoz, Open WebUI.
- **3 different access patterns**: public HTTPS (SPL via Caddy), Tailscale-only (rocketman services), localhost-only (cadvisor on rocketman).
- **No single hostname resolves everything**: rocketman services use Tailscale DNS, SPL services use a real domain.

### Drift risk

A static Markdown file (like `SERVICES.md`, which is already partially stale per `AGENTS.md`) drifts immediately when ports change, services are added/removed, or bind addresses change. The repo has no existing service index, and `SERVICES.md` bottom half describes an old pi-services/Cloudflare layout that no longer exists.

---

## Candidate approaches

### A. Static Markdown/HTML in the repo

A Markdown file (updated `SERVICES.md` or new `SERVICE_INDEX.md`) with all URLs.

**Pros:** Zero infra cost, no new container, version-controlled.
**Cons:** No health checks, no status indicators, drifts immediately, no search/bookmark UX. `file://` bookmarks don't work across machines. Would need to be served by something.

**Verdict:** Honest baseline but not what was asked for — the whole point is the owner *keeps losing track*, and static Markdown won't solve that.

### B. Static HTML served from an existing service

Serve a small HTML file from an already-running container (e.g. add an nginx location to the Caddy config on sweetpaintedlady, or mount an HTML file into the yt-dlp container).

**Pros:** No new container. Config-as-code fits the repo's `generate_config.sh` pattern. Single bookmark URL (e.g. `https://index.${DOMAIN}`).
**Cons:** Is this "app code"? The repo says "infra/config-templates ONLY, no application code" — but a single static HTML file is closer to config than app code. Still manually maintained (drift).

**Verdict:** Plausible as a delivery mechanism, but doesn't solve the drift problem.

### C. Purpose-built self-hosted homelab dashboards

Evaluated against: **actively maintained**, **config-as-code**, **Authelia-compatible**, **operational cost**.

#### Homer ([bastienwirtz/homer](https://github.com/bastienwirtz/homer))

- **What it is:** Dead-simple static HTML/JS dashboard from a single `config.yml`. Serves compiled static assets from a tiny Alpine container.
- **Latest release:** v26.08.3 (August 2026 — actively maintained, semantic calendar versioning).
- **Config:** Single YAML file (`assets/config.yml`), groups + items, icon support, optional "smart cards" for services like Pi-hole, Proxmox. No Docker socket needed.
- **Auth:** No built-in auth. Explicitly designed to sit behind a reverse proxy; has `proxy.useCredentials` and `connectivityCheck: true` for auth proxy support. Works with Authelia forward-auth (community-confirmed).
- **Resource cost:** ~15 MB RAM, ~5 MB container image. Single container, no DB.
- **Docker auto-discovery:** No — all config is manual YAML.
- **Primary sources:**
  - GitHub: https://github.com/bastienwirtz/homer
  - Releases: https://github.com/bastienwirtz/homer/releases
  - Docker Hub: https://hub.docker.com/r/b4bz/homer
  - Config docs: https://github.com/bastienwirtz/homer/blob/main/docs/configuration.md

#### Homepage ([gethomepage/homepage](https://github.com/gethomepage/homepage))

- **What it is:** Modern application dashboard with 100+ service integrations, Docker auto-discovery via labels, live status/stats widgets.
- **Latest release:** Active development, frequent releases. Made by Zensical (formerly gethomepage).
- **Config:** YAML files under `/app/config/` (`settings.yaml`, `services.yaml`, `docker.yaml`, `widgets.yaml`). Supports Docker label auto-discovery (`homepage.*` labels on containers).
- **Auth:** Built-in OIDC/OAuth2 provider (supports Authelia as OIDC provider), plus simple password auth. Has `HOMEPAGE_ALLOWED_HOSTS` for host header validation behind reverse proxies.
- **Resource cost:** Node.js-based, ~50-100 MB RAM. Single container, no DB.
- **Docker auto-discovery:** Yes — reads Docker socket, auto-discovers containers with `homepage.*` labels.
- **Drift mitigation:** Can auto-discover running containers from Docker socket (best-in-class for this problem).
- **Authelia compatibility:** Confirmed working behind Authelia forward-auth (community reports). Also has native OIDC.
- **Primary sources:**
  - GitHub: https://github.com/gethomepage/homepage
  - Docs: https://gethomepage.dev/
  - Docker config: https://gethomepage.dev/configs/docker/
  - Auth docs: https://gethomepage.dev/configs/settings/#authentication

#### Glance ([glanceapp/glance](https://github.com/glanceapp/glance))

- **What it is:** Lightweight Go-based dashboard for feeds + service status. Single binary, minimal JS.
- **Latest release:** Active development, 977 commits on main. AGPL-3.0.
- **Config:** YAML (`glance.yml` + page files), includes Docker container status widget, server stats widget.
- **Auth:** As of mid-2026, gained built-in auth (`secret-key` + `password-hash` in config). Previously had no auth — community workaround was Authelia/Authentik in front.
- **Resource cost:** <20 MB binary, ~30-50 MB RAM. Single container, no DB.
- **Docker auto-discovery:** No — Docker container status widget is manually configured.
- **Primary sources:**
  - GitHub: https://github.com/glanceapp/glance
  - Config docs: https://github.com/glanceapp/glance/blob/main/docs/configuration.md

#### Dashy ([Lissy93/dashy](https://github.com/Lissy93/dashy))

- **What it is:** Highly customizable dashboard with 26.5k GitHub stars, UI editor, themes, multi-page support.
- **Latest release:** Active development, 4,781 commits. MIT license.
- **Config:** YAML (`conf.yml`) + UI editor. Docker auto-discovery not a primary feature.
- **Auth:** Built-in basic auth + Keycloak SSO + alternative auth methods.
- **Resource cost:** Node.js-based, Vite build system. Heavier than Homer/Glance.
- **Verdict:** Feature-rich but heavier than needed. Over-engineered for a simple service index.

### D. Browser-level solution (bookmark folder)

**Pros:** Zero infrastructure, zero maintenance, zero drift (browser bookmarks don't lie). Works across all reachability patterns natively (Tailscale DNS resolves, HTTPS works). No config-as-code tension.
**Cons:** No status indicators, no at-a-glance view. Not "cute."
**Verdict:** Honestly the cheapest solution that actually works. But the owner asked for a dashboard experience.

### E. Tailscale Serve / Tailscale Funnel

Tailscale Serve can expose a local HTTP service on the tailnet with a nice URL. Could serve a static index.

**Pros:** No extra container on rocketman, tailnet-native auth (device-level), works naturally with existing Tailscale DNS.
**Cons:** Only works on the tailnet (doesn't cover sweetpaintedlady's public services), still needs a static file to serve.
**Verdict:** Complements but doesn't replace a dashboard.

---

## Comparison

| Criterion | Homer | Homepage | Glance | Bookmark folder |
|---|---|---|---|---|
| Setup effort in this repo | 1 compose block + 1 YAML | 1 compose block + 2-3 YAMLs + Docker socket | 1 compose block + 1 YAML | 0 |
| Drift risk | Manual YAML — will drift | Docker auto-discovery mitigates | Manual YAML — will drift | None (browser-native) |
| Moving parts added | 1 container, no DB, ~15 MB RAM | 1 container, no DB, ~50-100 MB RAM + Docker socket | 1 container, no DB, ~30-50 MB RAM | 0 |
| Authelia compatible | Yes (behind forward-auth) | Yes (native OIDC + forward-auth) | Yes (built-in auth or forward-auth) | N/A |
| Single bookmarkable URL | Yes (e.g. `http://rocketman:PORT`) | Yes | Yes | N/A (folder) |
| Health/status indicators | Basic HTTP ping per item | Live Docker stats + HTTP status | Container status widget | No |
| Config-as-code fit | Excellent (single YAML) | Good (multiple YAMLs + labels) | Good (YAML) | N/A |
| Cross-host coverage | Can list any URL | Can list any URL + auto-discover local Docker | Can list any URL | Works everywhere |
| "App code" by this repo's definition | Static assets + config = borderline config | More moving parts but still config files | Binary + config = borderline config | N/A |

---

## Verdict

**Homepage** (gethomepage.dev) is the best technical fit because:
1. **Docker auto-discovery** via labels eliminates the drift problem — the dashboard updates itself when containers change. No other candidate does this.
2. The repo already uses Docker labels for nothing today, so there's no conflict.
3. Authelia-compatible (both forward-auth and native OIDC).
4. Config-as-code YAML fits the repo's philosophy.

**But** — the repo is explicitly "infra/config-templates ONLY, no application code." Homepage requires mounting the Docker socket, which is a non-trivial security surface and a new pattern for this repo. It's the right tool but the wrong fit for this repo's constraints.

**Homer** is the pragmatic winner:
1. **Smallest surface area:** 15 MB RAM, single YAML, no Docker socket, no DB. Fits the "infra repo" ethos better than Homepage.
2. **Config-as-code native:** A single `config.yml` that can be checked into the repo (or generated by `generate_config.sh`).
3. **Authelia compatible:** Designed to sit behind forward-auth proxies.
4. **Drift is the trade-off:** Manual YAML means it will drift, but the cost of maintaining a ~30-line YAML is near-zero compared to the pain of currently having *no* index at all.
5. **Can be served by existing infra:** On rocketman, bind to `TAILNET_BIND_ADDR` like the other services. On sweetpaintedlady, add a Caddy route (e.g. `index.${DOMAIN}`).

### Concrete minimal step

1. Add a `services/homer/` directory with:
   - `docker-compose.homer.yml` (single container, config bind mount, port on TAILNET_BIND_ADDR for rocketman)
   - `services/homer/config.yml` (the service index YAML, with all 6 user-facing URLs grouped by host)
2. Include the homer overlay in the deploy chain for rocketman.
3. On sweetpaintedlady, add a `index.${DOMAIN}` Caddy block with Authelia forward-auth.
4. The `config.yml` becomes a generated file (or just hand-maintained — it's ~30 lines). The cost of updating it when a service changes is a one-line edit, and it'll be immediately visible next time someone checks the dashboard.

The alternative — just creating a bookmark folder — would be honest and cost nothing, but would leave the "at-a-glance status" problem unsolved. Homer gives the dashboard UX with minimal new moving parts.
