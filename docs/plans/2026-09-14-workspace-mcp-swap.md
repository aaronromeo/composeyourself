# Self-hosted Google Workspace MCP Swap — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four Google-hosted Workspace MCP connections in Open WebUI with one self-hosted `taylorwilsdon/google_workspace_mcp` container using single-user server OAuth, removing the Workspace Developer Preview blocker and all per-user OWUI OAuth machinery.

**Architecture:** A new `google-workspace-mcp` compose service on sweetpaintedlady (built from the upstream git tag) runs its own Google OAuth consent flow and stores one token server-side. Open WebUI connects with `auth_type: "none"` over the internal `cys-service` network — no Authorization header, no Fernet blobs, no `oauth_session` rows. Caddy exposes exactly one public path (`/oauth2callback`) for the browser consent redirect; the unauthenticated `/mcp` endpoint is internal-only.

**Tech Stack:** Docker Compose (base + `docker-compose.sweetpaintedlady.yml` overlay), Caddy 2.11.1, Open WebUI v0.11.1, `taylorwilsdon/google_workspace_mcp` v1.26.1 (Python/FastMCP, git-URL build context).

**Plan location note:** saved under `docs/plans/` (repo convention for dated design docs per AGENTS.md), not the skill-default `docs/superpowers/plans/`.

## Global Constraints

- **Host chain:** never `docker compose up` with a single file. sweetpaintedlady = `-f docker-compose.yml -f docker-compose.sweetpaintedlady.yml`. The only local sanity checks are `docker compose <chain> config`, `caddy validate` in a container, and running the generator script.
- **No build/test/lint** exists for this repo (AGENTS.md). Verification = compose config renders + generator output parses + on-host healthcheck + one real end-to-end tool call.
- **Auth model is decided — do not re-litigate:** single-user server OAuth; OWUI `auth_type: "none"` (verified: `build_tool_server_headers` in `backend/open_webui/utils/tools.py` v0.11.1 line ~1400 adds no header for `auth_type == 'none'`). Trade-off accepted: all OWUI users share the server's single Google identity.
- **Security invariant:** workspace-mcp "legacy" HTTP mode (no `MCP_ENABLE_OAUTH21`) has **no protocol auth on `/mcp`**. Caddy must 404 every public path except `/oauth2callback`. `/mcp` is reachable only on the internal bridge network.
- **Decisions from the committed record** (`docs/specs/assistant/2026-09-14-google-workspace-mcp-decision-history.md`, commit `d96e1b0`): service/container name `google-workspace-mcp`; `scripts/gcp-mcp-setup.sh` wizard is deleted; the per-user user guide is rewritten; the 2026-09-12 design doc gets a superseded banner. Public hostname is `workspace-mcp.{$DOMAIN}` (handoff suggestion; `auth.{$DOMAIN}` precedent).
- **Generated files are never hand-edited**; the generator script is the source (called by `generate_config.sh` every deploy). `.env` is never committed.
- **Verified upstream facts** (fetched from the v1.26.1 tag / `main` on 2026-09-14 — do not re-derive):
  - PyPI `workspace-mcp` **1.26.1**; git tag `v1.26.1` exists; no published Docker image; root `Dockerfile`: `python:3.11-slim`, non-root `app` user, `EXPOSE 8000` (`PORT` honored), healthcheck `curl -f http://localhost:${PORT:-8000}/health`, token store dir `/app/store_creds` (chown'd `app`), `ENTRYPOINT ["/bin/sh","-c"]`, `CMD ["uv run main.py --transport streamable-http ${TOOL_TIER:+--tool-tier \"$TOOL_TIER\"} ${TOOLS:+--tools $TOOLS}"]`.
  - Env contract: `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `GOOGLE_OAUTH_REDIRECT_URI` (default is `http://localhost:8000/oauth2callback` — **must** be set), `USER_GOOGLE_EMAIL` (server-side default injected into every tool; also sets server instructions), `WORKSPACE_MCP_HOST` (legacy HTTP mode binds `127.0.0.1` unless explicitly set), `WORKSPACE_MCP_CREDENTIALS_DIR` (default `~/.google_workspace_mcp/credentials`), `TOOL_TIER`/`TOOLS` (CMD expansion, docker-native), `PORT` (default 8000). **`MCP_ENABLE_OAUTH21` stays unset** — that's the multi-user PKCE mode we explicitly rejected.
  - MCP endpoint: `http://<host>:8000/mcp` (README Claude Code example). Health: `/health`. Google callback: `/oauth2callback` (registered as a custom route in legacy mode).
  - First-use flow: a tool call with no stored credentials returns an "ACTION REQUIRED" message containing the `accounts.google.com` authorization URL (with `login_hint=USER_GOOGLE_EMAIL`, `access_type=offline`, PKCE, state bound to the MCP session). User opens it in their browser, consents, Google redirects to `GOOGLE_OAUTH_REDIRECT_URI`, the server exchanges the code and stores the credential (keyed by the account email) in the credential store. Retry the tool call → works. Subsequent sessions load from the store by email.
  - `OAUTHLIB_INSECURE_TRANSPORT` is only needed for `http://localhost` redirect URIs; ours is HTTPS, so do NOT set it.
  - Tool selection: `--tool-tier core --tools gmail calendar docs sheets drive` = core-tier tools for the 5 services the old hosted connections covered (gmail/calendar/docs/sheets + drive, which docs/sheets need for file discovery). Keep context lean; avoid Chat/Custom-Search/Apps-Script noise. Scope upgrade = edit `TOOLS`/`TOOL_TIER` in compose.
  - Compose git-URL build context (`context: https://github.com/...git#v1.26.1`) is supported by `docker compose build` (runs in `update.sh` line 92 and implicitly at first `up -d`); `deploy.sh` builds `--no-cache`. No submodule needed — the pin lives in the compose file like the other image pins.
  - OWUI MCP connection facts (v0.11.1 source, `utils/middleware.py` `connect_mcp_server`): the connection's `url` field is passed **as-is** to the streamable-http client — it must be the full endpoint `http://google-workspace-mcp:8000/mcp`. The `path` field is only used by `openapi`-type connections. MCP servers surface to users as a pseudo-tool `server:mcp:<info.id>`; missing `access_grants` ⇒ admin-only (commit `7e4453a`), so keep the wildcard user grant.

---

### Task 1: Add the `google-workspace-mcp` compose service

**Files:**
- Modify: `docker-compose.sweetpaintedlady.yml` (add service after `searxng`, ~line 173; add volume to the `volumes:` block at the bottom)

**Interfaces:**
- Produces: service `google-workspace-mcp` on `cys-service`, HTTP on `google-workspace-mcp:8000` (`/mcp`, `/health`, `/oauth2callback`), named volume `google_workspace_mcp_creds` mounted at `/app/store_creds`. Consumes `.env` vars `GOOGLE_MCP_CLIENT_ID`, `GOOGLE_MCP_CLIENT_SECRET`, `DOMAIN`, `USER_GOOGLE_EMAIL`.

- [ ] **Step 1: Add the service definition**

Insert after the `searxng` service block in `docker-compose.sweetpaintedlady.yml` (before the Caddy block):

```yaml
  # Self-hosted Google Workspace MCP server (taylorwilsdon/google_workspace_mcp,
  # pinned to the v1.26.1 git tag). Replaces Google's Developer-Preview-gated
  # hosted MCP endpoints — see docs/specs/assistant/2026-09-14-google-workspace-mcp-decision-history.md
  # and docs/plans/2026-09-14-workspace-mcp-swap.md.
  #
  # Single-user server OAuth: the server runs its own Google consent flow and
  # stores ONE token server-side (keyed by USER_GOOGLE_EMAIL). Open WebUI
  # connects with auth_type "none" — no per-user OAuth state in OWUI at all.
  # All OWUI users share this single Google identity (accepted trade-off).
  #
  # This "legacy" HTTP mode has NO protocol auth on /mcp, so the endpoint must
  # never be exposed publicly. Caddy proxies ONLY /oauth2callback (the browser
  # consent redirect); Open WebUI reaches /mcp over the internal cys-service
  # network. MCP_ENABLE_OAUTH21 stays unset — that's the multi-user PKCE mode
  # we explicitly rejected.
  google-workspace-mcp:
    build:
      context: https://github.com/taylorwilsdon/google_workspace_mcp.git#v1.26.1
    image: google-workspace-mcp:1.26.1
    container_name: google-workspace-mcp
    restart: unless-stopped
    logging: *default-logging
    expose:
      - "8000"
    volumes:
      # Google OAuth token store — persists the refresh token across
      # restarts/rebuilds so consent is a one-time step.
      - google_workspace_mcp_creds:/app/store_creds
    environment:
      # Reuse the GCP OAuth client the old wizard created (write scopes
      # already registered, consent screen published to production).
      - GOOGLE_OAUTH_CLIENT_ID=${GOOGLE_MCP_CLIENT_ID}
      - GOOGLE_OAUTH_CLIENT_SECRET=${GOOGLE_MCP_CLIENT_SECRET}
      # Browser-facing callback, routed via Caddy at workspace-mcp.$DOMAIN.
      # Must also be registered in the GCP OAuth client's redirect URIs
      # (manual step, see plan Task 7).
      - GOOGLE_OAUTH_REDIRECT_URI=https://workspace-mcp.${DOMAIN}/oauth2callback
      # The single Google account the server acts as. Server-side default:
      # makes user_google_email optional on every tool and injects it
      # automatically, so models never need to ask for an email.
      - USER_GOOGLE_EMAIL=${USER_GOOGLE_EMAIL}
      # Core tier for the 5 services the old hosted connections covered.
      # The Dockerfile CMD expands TOOL_TIER/TOOLS into main.py args.
      # Widen by editing this list (see upstream tool_tiers.yaml).
      - TOOL_TIER=core
      - TOOLS=gmail calendar docs sheets drive
      # Legacy HTTP mode binds loopback unless told otherwise; the container
      # must listen on the bridge network for OWUI + Caddy to reach it.
      - WORKSPACE_MCP_HOST=0.0.0.0
      - WORKSPACE_MCP_CREDENTIALS_DIR=/app/store_creds
    deploy:
      resources:
        limits:
          memory: 512M
    networks:
      - cys-service
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

Add to the `volumes:` block at the bottom of the file:

```yaml
  google_workspace_mcp_creds:
    # Persist the workspace-mcp Google OAuth token store
```

- [ ] **Step 2: Sanity-check the compose chain renders**

Run (from the repo root; env vars only silence interpolation warnings — no real secrets needed locally):

```bash
DOMAIN=example.com SUBDOMAIN=app TS_AUTHKEY=x OAUTH_CLIENT_SECRET=x \
OPENROUTER_API_KEY=x USER_GOOGLE_EMAIL=someone@example.com \
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml config >/dev/null && echo OK
```

Expected: `OK` (no YAML errors; warnings about other unset vars are fine).

- [ ] **Step 3: Commit**

```bash
git add docker-compose.sweetpaintedlady.yml
git commit -m "Add self-hosted google-workspace-mcp service"
```

---

### Task 2: Caddy — expose only the OAuth callback

**Files:**
- Modify: `services/caddy/Caddyfile` (append a new site block after the `auth.{$DOMAIN}` block)

**Interfaces:**
- Produces: public HTTPS site `workspace-mcp.{$DOMAIN}` where ONLY `/oauth2callback` proxies to `google-workspace-mcp:8000`; all other paths (including `/mcp`) return 404. Requires a DNS A record for `workspace-mcp.<DOMAIN>` (manual step, Task 7).

- [ ] **Step 1: Append the site block**

```caddyfile
# Self-hosted Google Workspace MCP — public ONLY for the OAuth callback.
# Google redirects the user's browser to /oauth2callback after consent.
# The MCP endpoint (/mcp) is deliberately NOT proxied: legacy-mode
# workspace-mcp has no protocol auth, and Open WebUI reaches it over the
# internal cys-service network (http://google-workspace-mcp:8000/mcp).
# Everything else 404s so the unauthenticated /mcp endpoint is never
# exposed to the internet.
workspace-mcp.{$DOMAIN} {
    handle /oauth2callback {
        reverse_proxy google-workspace-mcp:8000
    }
    # Catch-all: handle blocks are mutually exclusive and ordered, so this
    # takes everything the first block didn't match.
    handle {
        respond 404
    }
}
```

- [ ] **Step 2: Validate the Caddyfile**

```bash
docker run --rm -e SUBDOMAIN=app -e DOMAIN=example.com \
  -v "$(pwd)/services/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2.11.1 caddy validate --config /etc/caddy/Caddyfile
```

Expected: `Valid configuration`.

- [ ] **Step 3: Commit**

```bash
git add services/caddy/Caddyfile
git commit -m "Expose only the workspace-mcp OAuth callback via Caddy"
```

---

### Task 3: Rewrite the connection generator

The old script built four `oauth_2.1_static` connections with Fernet-encrypted blobs via an ephemeral `docker run` of the pinned OWUI image. The new one emits a single static `auth_type: "none"` connection. Everything Google-related moves into the workspace-mcp container; OWUI only needs a pointer at it.

**Files:**
- Rewrite: `scripts/gen-openwebui-mcp-connections.sh`
- Modify: `docker-compose.sweetpaintedlady.yml` (openwebui `env_file` comment, lines ~67-71)

**Interfaces:**
- Produces: `services/agenticui/generated.env` containing either a comment-only line (when `USER_GOOGLE_EMAIL` is unset — rocketman, unconfigured hosts) or `TOOL_SERVER_CONNECTIONS='<single JSON connection>'` (single line — docker env_file cannot parse multi-line values). Keeps ensuring `services/agenticui/.webui_secret_key` (44-char urlsafe base64) — OWUI's session-signing key must persist across container recreates.
- Consumes: `USER_GOOGLE_EMAIL` (gate — "this host opted into workspace-mcp"), sourced from env (generate_config.sh exports `.env`) or `.env` directly.

- [ ] **Step 1: Replace the script body**

Replace the **entire content** of `scripts/gen-openwebui-mcp-connections.sh` with:

```bash
#!/usr/bin/env bash
# Generates services/agenticui/generated.env (TOOL_SERVER_CONNECTIONS) wiring
# Open WebUI to the self-hosted Google Workspace MCP server (the
# google-workspace-mcp service in docker-compose.sweetpaintedlady.yml).
#
# Called by generate_config.sh on every deploy. No-op (comment-only file) when
# USER_GOOGLE_EMAIL is not set — e.g. on hosts that don't run workspace-mcp.
#
# Design:
#   - The openwebui container reads its signing key from
#     WEBUI_SECRET_KEY_FILE=/app/backend/data/.webui_secret_key (set in
#     docker-compose.sweetpaintedlady.yml; start.sh default would be
#     /app/backend/.webui_secret_key — outside the volume, regenerated on
#     every container recreate, invalidating logins). This script ensures that
#     file exists so the key persists across deploys.
#   - The workspace-mcp server runs its own Google OAuth consent (single-user
#     server OAuth; one token stored server-side, keyed by USER_GOOGLE_EMAIL).
#     Open WebUI connects with auth_type "none": no Authorization header, no
#     per-user OAuth state (verified in open_webui/utils/tools.py v0.11.1,
#     build_tool_server_headers — auth_type 'none' adds no header). So this
#     script no longer builds Fernet blobs or runs the OWUI image; the JSON
#     below is the whole wiring.
#   - `url` is the FULL MCP endpoint: connect_mcp_server passes it straight to
#     the streamable-http client (the `path` field is only used by
#     openapi-type connections).
#   - access_grants: wildcard user grant = usable by every OWUI user. No grant
#     entry => admin-only in has_connection_access (see commit 7e4453a).
#   - Single line: docker env_file cannot parse multi-line values.
set -euo pipefail
cd "$(dirname "$0")/.."

DATA_DIR="services/agenticui"
KEY_FILE="${DATA_DIR}/.webui_secret_key"
OUT_FILE="${DATA_DIR}/generated.env"

# Env wins (generate_config.sh sources .env first); fall back to sourcing .env.
if [ -z "${USER_GOOGLE_EMAIL:-}" ] && [ -f .env ]; then
    set -a; . ./.env; set +a
fi

# 44-char urlsafe base64 = a valid Fernet key, used as-is by Open WebUI's
# derivation (len == 44 skips the sha256 path). Always ensured — the
# container needs it regardless of whether MCP is configured.
if [ ! -s "$KEY_FILE" ]; then
    echo "  • no .webui_secret_key found — generating one (container adopts it at next boot)"
    mkdir -p "$DATA_DIR"
    head -c 32 /dev/urandom | base64 | tr '+/' '-_' > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
fi

if [ -z "${USER_GOOGLE_EMAIL:-}" ]; then
    echo "  • USER_GOOGLE_EMAIL not set — no MCP connection"
    printf '# No MCP connections: USER_GOOGLE_EMAIL not configured\n' > "$OUT_FILE"
    exit 0
fi

printf "TOOL_SERVER_CONNECTIONS='%s'\n" '{"url":"http://google-workspace-mcp:8000/mcp","type":"mcp","auth_type":"none","config":{"enable":true,"access_grants":[{"principal_type":"user","principal_id":"*","permission":"read"}]},"info":{"id":"google-workspace","name":"Google Workspace","description":"Gmail, Calendar, Docs, Sheets, Drive via the self-hosted workspace-mcp server"}}' > "$OUT_FILE"
echo "  ✓ Generated 1 MCP connection (google-workspace) → $OUT_FILE"
```

- [ ] **Step 2: Fix the stale compose comment**

In `docker-compose.sweetpaintedlady.yml`, the openwebui `env_file` comment currently reads:

```yaml
    # Google Workspace MCP (Gmail/Calendar/Docs/Sheets) tool connections.
    # Written by generate_config.sh → scripts/gen-openwebui-mcp-connections.sh
    # from GOOGLE_MCP_* in .env. Always present (comment-only when unconfigured).
```

Replace with:

```yaml
    # Google Workspace MCP tool connection (single self-hosted server).
    # Written by generate_config.sh → scripts/gen-openwebui-mcp-connections.sh;
    # gated on USER_GOOGLE_EMAIL in .env. Comment-only when unconfigured.
```

- [ ] **Step 3: Run the generator and verify both branches**

```bash
chmod +x scripts/gen-openwebui-mcp-connections.sh

# Branch 1: unconfigured host
USER_GOOGLE_EMAIL= scripts/gen-openwebui-mcp-connections.sh
cat services/agenticui/generated.env
# Expected: "# No MCP connections: USER_GOOGLE_EMAIL not configured"

# Branch 2: configured host
USER_GOOGLE_EMAIL=someone@example.com scripts/gen-openwebui-mcp-connections.sh
cat services/agenticui/generated.env
# Expected: TOOL_SERVER_CONNECTIONS='{...}' containing "google-workspace-mcp:8000/mcp"
```

- [ ] **Step 4: Validate the emitted JSON**

```bash
eval "$(grep TOOL_SERVER_CONNECTIONS services/agenticui/generated.env)"
python3 -c "
import json, os
c = json.loads(os.environ['TOOL_SERVER_CONNECTIONS'])
assert len(c) == 1, c
assert c[0]['auth_type'] == 'none'
assert c[0]['url'] == 'http://google-workspace-mcp:8000/mcp'
assert c[0]['type'] == 'mcp'
assert c[0]['config']['enable'] is True
assert c[0]['config']['access_grants'][0]['principal_id'] == '*'
assert c[0]['info']['id'] == 'google-workspace'
print('connection JSON OK')
"
unset TOOL_SERVER_CONNECTIONS
```

Expected: `connection JSON OK`.

- [ ] **Step 5: Confirm nothing local was dirtied**

```bash
git status --short
```

Expected: only the two intended files modified (`services/agenticui/*` is gitignored, so generated output and the key file do not appear).

- [ ] **Step 6: Commit**

```bash
git add scripts/gen-openwebui-mcp-connections.sh docker-compose.sweetpaintedlady.yml
git commit -m "Rewrite MCP connection generator for self-hosted server"
```

---

### Task 4: `.env.example` — new vars, retired wizard instructions

**Files:**
- Modify: `.env.example` (replace the `GOOGLE_MCP_*` block, lines ~99-106)

**Interfaces:**
- Produces: documented contract for `USER_GOOGLE_EMAIL` (new, required on sweetpaintedlady) + `GOOGLE_MCP_CLIENT_ID/SECRET` (repurposed: now feed the workspace-mcp container as `GOOGLE_OAUTH_*`).

- [ ] **Step 1: Replace the GOOGLE_MCP block**

Replace this block in `.env.example`:

```
# Google Workspace MCP (Gmail / Calendar / Docs / Sheets via Open WebUI tool
# servers). One-time setup: run scripts/gcp-mcp-setup.sh — it walks you through
# creating the GCP project, consent screen, and OAuth client, and writes these.
# Redirect URIs follow: {WEBUI_URL}/oauth/clients/mcp:<service>/callback
# See docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md
GOOGLE_CLOUD_PROJECT=
GOOGLE_MCP_CLIENT_ID=
GOOGLE_MCP_CLIENT_SECRET=
```

with:

```
# Google Workspace MCP (self-hosted google-workspace-mcp container on
# sweetpaintedlady — see docs/plans/2026-09-14-workspace-mcp-swap.md).
# These feed the container as GOOGLE_OAUTH_CLIENT_ID/SECRET (single-user
# server OAuth: one token stored server-side, shared by all assistant users).
#
# Fresh-setup summary (the old gcp-mcp-setup.sh wizard is retired; full
# walkthrough preserved in git history):
#   1. GCP project with billing; enable: gmail.googleapis.com,
#      calendar-json.googleapis.com, docs.googleapis.com,
#      sheets.googleapis.com, drive.googleapis.com
#   2. OAuth consent screen: External, PUBLISHED to production (unpublished
#      "Testing" mode expires refresh tokens after 7 days).
#   3. OAuth client (Web application) with authorized redirect URI:
#      https://workspace-mcp.<your DOMAIN>/oauth2callback
GOOGLE_CLOUD_PROJECT=
GOOGLE_MCP_CLIENT_ID=
GOOGLE_MCP_CLIENT_SECRET=

# The single Google account the workspace-mcp server acts as. One token,
# stored server-side, shared by every assistant user (single-user server
# OAuth). Set on sweetpaintedlady only; unset = Google Workspace tools
# disabled (the generator emits a comment-only generated.env).
USER_GOOGLE_EMAIL=
```

- [ ] **Step 2: Commit**

```bash
git add .env.example
git commit -m "Update env example for workspace-mcp single-user OAuth"
```

---

### Task 5: Retire the wizard, mark old docs superseded

Per the committed decision record (`d96e1b0`): delete the wizard (its Stages 1/5/6 now point at dead redirect URIs and hosted APIs; git history preserves it; the `.env.example` comment from Task 4 carries the fresh-setup summary), banner the old design doc, and rewrite the user guide for the new consent flow.

**Files:**
- Delete: `scripts/gcp-mcp-setup.sh`
- Modify: `docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md` (prepend banner)
- Rewrite: `docs/specs/assistant/2026-09-13-google-workspace-oauth-user-guide.md`

**Interfaces:**
- Produces: docs consistent with the new flow; no script references `gcp-mcp-setup.sh` afterwards (verified in Step 4).

- [ ] **Step 1: Delete the wizard**

```bash
git rm scripts/gcp-mcp-setup.sh
```

- [ ] **Step 2: Prepend the superseded banner to the design doc**

Insert at the very top of `docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md` (above the existing `# Open WebUI Google Workspace Access — Research Findings` heading):

```markdown
> **STATUS: SUPERSEDED (2026-09-14).** The per-user OAuth design described
> here (four hosted Google MCP connections, `oauth_2.1_static`, per-user
> `oauth_session` rows) was replaced by a single self-hosted workspace-mcp
> container using single-user server OAuth. See
> [docs/plans/2026-09-14-workspace-mcp-swap.md](../../plans/2026-09-14-workspace-mcp-swap.md),
> [2026-09-14-google-workspace-mcp-alternatives.md](2026-09-14-google-workspace-mcp-alternatives.md),
> and
> [2026-09-14-google-workspace-mcp-decision-history.md](2026-09-14-google-workspace-mcp-decision-history.md).
> Kept for historical context.
```

- [ ] **Step 3: Rewrite the user guide**

Replace the **entire content** of `docs/specs/assistant/2026-09-13-google-workspace-oauth-user-guide.md` with:

```markdown
# Google Workspace access — user guide

Gmail, Calendar, Docs, and Sheets are connected through a self-hosted
workspace-mcp server using single-user server OAuth: one Google account is
authorized once, server-side, and every assistant user shares it. No admin
action is needed beyond deploying the stack.

## To connect the Google account (one-time)

1. Ask the assistant anything that needs Google (e.g. *"check my calendar
   for tomorrow"*). The first time, it replies with an **Authorization URL**.
2. Open that link in your browser, sign in with the household Google account,
   and Allow. The first time Google shows *"Google hasn't verified this
   app"*: click **Advanced → Go to ... (unsafe)** → **Allow** — the app is
   ours; the warning appears because the consent screen isn't reviewed by
   Google.
3. Tell the assistant to retry. Done — the token is stored server-side and
   refreshed automatically; you never see the consent screen again unless
   access is revoked.

If the link sits unused for a while the attempt expires ("Missing OAuth
state"); just ask again to get a fresh one.

## Using the tools

Enable **Google Workspace** in the chat's tools panel, then ask. Read and
write are both enabled (search/send email, create/edit events, edit
docs/sheets). The old per-service tools (Gmail / Calendar / Docs / Sheets)
no longer exist — re-enable **Google Workspace** once if you had the old
ones pinned per chat.

If a consent ever fails with `redirect_uri_mismatch`, tell the admin the
exact URI Google displays so it can be added to the OAuth client in Google
Cloud Console.
```

- [ ] **Step 4: Confirm no dangling references to the wizard**

```bash
grep -rn "gcp-mcp-setup" --include='*.sh' --include='*.yml' --include='*.example' . | grep -v docs/
```

Expected: no output (the generator's new text no longer mentions it; docs hits are historical records and acceptable).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Retire GCP wizard, mark old Google MCP docs superseded"
```

---

### Task 6: Full local sanity pass

**Files:** none (verification only)

- [ ] **Step 1: Compose chain renders with the generated env in place**

```bash
DOMAIN=example.com SUBDOMAIN=app TS_AUTHKEY=x OAUTH_CLIENT_SECRET=x \
OPENROUTER_API_KEY=x USER_GOOGLE_EMAIL=someone@example.com \
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml config >/dev/null && echo OK
```

Expected: `OK`.

- [ ] **Step 2: Caddyfile still validates**

```bash
docker run --rm -e SUBDOMAIN=app -e DOMAIN=example.com \
  -v "$(pwd)/services/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2.11.1 caddy validate --config /etc/caddy/Caddyfile
```

Expected: `Valid configuration`.

- [ ] **Step 3: Generator output still parses** (re-run Task 3 Step 4 validation)

Expected: `connection JSON OK`.

---

### Task 7: Manual external steps (user-executed — the agent cannot do these)

**Files:** none in the repo. These gate real deployment; do them before or during Task 8.

- [ ] **Step 1: GCP redirect URI**

Google Cloud Console → APIs & Services → Credentials → the existing OAuth client (the one whose ID/SECRET is in the host's `.env` as `GOOGLE_MCP_CLIENT_ID/SECRET`) → **Authorized redirect URIs** → add:

```
https://workspace-mcp.<DOMAIN>/oauth2callback
```

Optionally remove the four now-dead `{WEBUI_URL}/oauth/clients/mcp:google-*/callback` URIs.

- [ ] **Step 2: DNS record**

Add an A record `workspace-mcp.<DOMAIN>` → sweetpaintedlady's public IP (the same IP the other `*.<DOMAIN>` records point at). Caddy's ACME HTTP-01 challenge needs it before the new site block can issue a cert.

- [ ] **Step 3: Host `.env`**

On sweetpaintedlady (`/opt/docker/composeyourself/.env`), add:

```
USER_GOOGLE_EMAIL=<the household Google account>
```

(`GOOGLE_MCP_CLIENT_ID/SECRET` are already there — the compose mapping reuses them.)

---

### Task 8: Deploy and verify end-to-end

**Files:** none in the repo. All commands run on sweetpaintedlady as `dockerops` in `/opt/docker/composeyourself` (the handoff's deploy pattern: `update.sh` early-exits after a manual pull, so use `generate_config.sh` + `restart.sh`).

- [ ] **Step 1: Pull and regenerate**

```bash
git pull
./generate_config.sh
```

Expected: among the output, `✓ Generated 1 MCP connection (google-workspace) → services/agenticui/generated.env`.

- [ ] **Step 2: Validate config on the host**

```bash
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml config >/dev/null && echo OK
```

Expected: `OK` (this also re-reads the host `.env`, catching a missing `USER_GOOGLE_EMAIL`).

- [ ] **Step 3: Restart the stack (first run builds the workspace-mcp image)**

```bash
./restart.sh sweetpaintedlady
```

Expected: `up -d` builds `google-workspace-mcp:1.26.1` from the git tag (a few minutes — `uv sync` inside the build), stack comes up, preset seeding runs.

- [ ] **Step 4: Healthcheck**

```bash
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml ps
```

Expected: `google-workspace-mcp` (healthy). If it cycles: `docker logs google-workspace-mcp` — the startup banner shows mode/transport/credentials-dir; a permission error on the store means the volume didn't mount at `/app/store_creds`.

Also verify the public gate:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://workspace-mcp.<DOMAIN>/mcp   # from any machine
```

Expected: `404` (Caddy refuses to proxy it — this is the security invariant).

- [ ] **Step 5: End-to-end tool call (the real verification gate)**

In Open WebUI (via the browser):

1. New chat → enable **Google Workspace** in the tools panel.
2. Ask: *"What's the newest email in my inbox?"*
3. Expected first response: an **Authorization URL** (the model relays the ACTION REQUIRED message).
4. Open the URL, sign in with `USER_GOOGLE_EMAIL`, Allow (with the unverified-app bypass).
5. Browser lands on the callback success page (`workspace-mcp.<DOMAIN>/oauth2callback`).
6. Ask again: *"What's the newest email in my inbox?"* → the model returns a real subject/sender.

If step 6 fails, check `docker logs google-workspace-mcp` for `OAuth callback` / credential-store lines before touching anything else.

- [ ] **Step 6: Regression check — the rest of the stack still works**

- OWUI loads, login works (the `.webui_secret_key` persisted — if everyone got logged out, the key file logic broke).
- SearXNG web search in a chat still works (unchanged wiring, cheap to confirm).

---

## Deliberately skipped (YAGNI — record only)

- **`deploy.sh` service-list echo** (`📦 Services: Open WebUI, Caddy, Authelia`) — cosmetic first-deploy banner; not worth a diff.
- **OTel wiring for workspace-mcp** — upstream supports `--extra otel` + `OTEL_*` env; the edge collector already tails its container logs automatically. Add OTLP tracing only if the server misbehaves.
- **`--single-user` flag** — unnecessary: `USER_GOOGLE_EMAIL` injection makes every tool call resolve the same server-side credential; the stock Dockerfile CMD works unmodified.
- **Research doc edits** — dated snapshot; version drift (v1.20.1 → v1.26.1) is corrected by this plan's verified-facts section and the decision-history doc.
- **Removing the four dead GCP redirect URIs / hosted MCP API enables** — optional console hygiene (Task 7 Step 1).
