# Google Workspace MCP Alternatives — Research Findings

**Date:** 2026-09-14
**Scope:** Alternatives to Google's hosted Developer Preview MCP servers for Gmail/Calendar/Docs/Sheets access via Open WebUI
**Method:** Primary sources only — Google official docs, Open WebUI source (v0.11.1), GitHub repos of candidate MCP servers

---

## Executive recommendation

**Option 1 (self-hosted MCP via taylorwilsdon/google\_workspace\_mcp) is the better path.** It replaces all four Google hosted MCP servers with a single container, uses the same per-user OAuth consent flow, speaks Streamable HTTP (compatible with Open WebUI's `TOOL_SERVER_CONNECTIONS`), and wraps the underlying REST APIs that are all Generally Available — no Developer Preview enrollment needed. Option 2 (direct REST calls from OWUI Functions) would require expanding Google SSO scopes to include Workspace API scopes (a breaking change for all users), writing and maintaining four separate Python tool modules with token refresh logic, rate-limit handling, and error recovery. Option 1 is a container swap plus a config edit; Option 2 is a new code surface with ongoing maintenance burden.

---

## Current state

**Hosted MCP wiring (what we're leaving):**
- `scripts/gen-openwebui-mcp-connections.sh` generates `TOOL_SERVER_CONNECTIONS` with 4 connections (`google-gmail`, `google-calendar`, `google-docs`, `google-sheets`) pointing at `gmailmcp.googleapis.com/mcp/v1`, `calendarmcp.googleapis.com/mcp/v1`, `docsmcp.googleapis.com/mcp/v1`, `sheetsmcp.googleapis.com/mcp/v1` ([scripts/gen-openwebui-mcp-connections.sh:87-105](scripts/gen-openwebui-mcp-connections.sh)).
- Auth type is `oauth_2.1_static` with per-user OAuth sessions stored in the `oauth_session` table keyed by `(user_id, provider)` where provider = `mcp:<server_id>` ([docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md](docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md)).
- The Developer Preview enrollment requirement is documented at [developers.google.com/workspace/preview](https://developers.google.com/workspace/preview): "Joining the program requires agreeing to the Program Terms, submitting an application form with Google Workspace and Google Cloud project details" and "features in Developer Preview may not be included in public applications prior to the General Availability announcement." The MCP servers are listed under the "MCP SERVERS" section of that page.

**Why hosted servers fail:** Google's hosted MCP servers refuse calls unless the GCP project is enrolled in the Developer Preview Program. Enrollment requires a Google Workspace email (not a personal @gmail.com), which we don't want to manage.

---

## Why self-hosted MCP servers bypass the Developer Preview requirement

**Verified from primary sources:** The Developer Preview requirement applies **only** to Google's hosted MCP server endpoints (`*mcp.googleapis.com`). The underlying REST APIs that those MCP servers wrap are all Generally Available and callable with a plain OAuth2 bearer token from any GCP project:

- **Gmail API:** "The Gmail API is publicly available!" — [Gmail API release notes](https://developers.google.com/workspace/gmail/release-notes), endpoint `https://gmail.googleapis.com` ([Gmail API reference](https://developers.google.com/workspace/gmail/api/reference/rest)).
- **Google Calendar API:** "The Google Calendar API is a RESTful API" — [Calendar API overview](https://developers.google.com/workspace/calendar/api/guides/overview), endpoint `https://www.googleapis.com/calendar/v3` ([Calendar API reference](https://developers.google.com/workspace/calendar/api/v3/reference)).
- **Google Sheets API:** "The Google Sheets API is a RESTful interface" — [Sheets API overview](https://developers.google.com/workspace/sheets/api/guides/concepts), endpoint `https://sheets.googleapis.com` ([Sheets API reference](https://developers.google.com/workspace/sheets/api/reference/rest)).
- **Google Docs API:** "The Google Docs API is now generally available" — [Docs API release notes](https://developers.google.com/docs/docs/release-notes), endpoint `https://docs.googleapis.com` ([Docs API reference](https://developers.google.com/workspace/docs/api/reference/rest)).
- **Google Drive API:** "The Google Drive API is now generally available" — [Drive API release notes](https://developers.google.com/workspace/drive/release-notes), endpoint `https://www.googleapis.com/drive/v3`.

All four APIs accept `Authorization: Bearer <access_token>` with standard OAuth 2.0 scopes ([Using OAuth 2.0 to Access Google APIs](https://developers.google.com/identity/protocols/oauth2)). No Developer Preview enrollment is needed for any of them.

---

## Option 1 — Self-hosted Google API MCP server(s)

### Candidate 1: taylorwilsdon/google\_workspace\_mcp (recommended)

| Attribute | Detail |
|---|---|
| **Repo** | [github.com/taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp) |
| **Stars** | ~3,100+ (most popular community Google Workspace MCP server) |
| **Maintenance** | Active, daily commits, v1.20.1 released April 2026 |
| **Language** | Python, FastMCP framework |
| **Published image** | No pre-built image; `docker build -t workspace-mcp .` from repo |
| **Services covered** | 12 services: Gmail, Calendar, Drive, Docs, Sheets, Slides, Forms, Tasks, Contacts, Apps Script, Chat, Custom Search |
| **Transport** | stdio (legacy) or Streamable HTTP (`--transport streamable-http`) |

**Auth modes supported:**
1. **Single-user** (`--single-user`): desktop OAuth client, local credential cache. One user only.
2. **OAuth 2.0 (default)**: multi-user, browser-based OAuth flow per session.
3. **OAuth 2.1** (`MCP_ENABLE_OAUTH21=true`): multi-user bearer-token auth over Streamable HTTP, PKCE, session stores. **This is the mode compatible with Open WebUI's `oauth_2.1_static` / `oauth_2.1` auth types.**
4. **External OAuth provider** (`EXTERNAL_OAUTH21_PROVIDER=true`): expects valid bearer tokens from an external IdP.
5. **Stateless** (`WORKSPACE_MCP_STATELESS_MODE=true`): memory-only sessions, token per request.

**How it maps to OWUI's existing wiring:**
- Run with `--transport streamable-http` + `MCP_ENABLE_OAUTH21=true` + `GOOGLE_OAUTH_CLIENT_ID`/`GOOGLE_OAUTH_CLIENT_SECRET`.
- The server exposes its own OAuth consent flow at `http://<host>:8000/oauth2callback`.
- In OWUI's `TOOL_SERVER_CONNECTIONS`, set `auth_type: "oauth_2.1"` (dynamic) or `auth_type: "oauth_2.1_static"` (static creds). The server's OAuth flow handles per-user token exchange; OWUI's `OAuthClientManager` fetches and refreshes tokens via `get_oauth_token(user_id, "mcp:<server_id>")` — the same mechanism used for the hosted servers today ([backend/open_webui/utils/middleware.py](https://github.com/open-webui/open-webui/blob/883f1dda/backend/open_webui/utils/middleware.py)).
- **Key difference:** The hosted servers use Google's DCR (Dynamic Client Registration) at `gmailmcp.googleapis.com`. A self-hosted server needs `auth_type: "none"` if the server manages its own OAuth entirely (OWUI doesn't need to handle the OAuth flow — the MCP server does), OR `auth_type: "oauth_2.1"` if OWUI's OAuth manager is wired to the self-hosted server's metadata endpoint. **Unverified:** whether OWUI's `oauth_2.1` auth type can discover OAuth metadata from a non-Google MCP server (the self-hosted server would need to expose `/.well-known/oauth-authorization-server`). If not, the simplest path is `auth_type: "none"` + the MCP server handles its own OAuth consent and token storage.

**Tool-surface parity with hosted servers (40 tools):**

| Service | Hosted tools | taylorwilsdon tools (core tier) |
|---|---|---|
| Gmail | `search_threads`, `get_message`, `get_thread`, `create_draft`, `list_drafts`, `list_labels`, `label_message`, `label_thread`, `unlabel_message`, `unlabel_thread` | `search_emails`, `read_emails`, `get_thread`, `send_email`, `create_draft`, `list_drafts`, `list_labels`, `apply_labels`, `delete_email`, `trash_email`, `move_email`, `list_threads`, `get_mail_digest`, `check_mail_updates`, `list_filters`, `create_filter`, `delete_filter`, `list_forwarding_addresses`, `get_vacation_settings` (120+ tools across 12 services, tiered by `--tool-tier core/extended/complete`) |
| Calendar | `list_events`, `search_events`, `get_event`, `create_event`, `update_event`, `delete_event`, `respond_to_event`, `list_calendars`, `suggest_time` | `search_events`, `read_events`, `get_calendar_digest`, `list_calendars`, `get_calendar_context`, `check_time_availability`, `create_event`, `update_event`, `respond_to_event`, `delete_event`, `find_common_free_slots` |
| Docs | `read_doc`, `update_doc` | `get_document`, `create_document`, `append_document_text`, `replace_document_text`, `batch_update_document` |
| Sheets | `get_values`, `get_spreadsheet`, `update_spreadsheet`, `update_values`, `update_formulas`, `insert_dimension` | `get_spreadsheet`, `create_spreadsheet`, `get_sheet_values`, `batch_get_sheet_values`, `append_sheet_values`, `update_sheet_values`, `batch_update_spreadsheet` |

**Verdict:** Equal or superior tool coverage. Single server covers all 4 services plus 8 more.

### Candidate 2: guinacio/mcp-google-workspace

| Attribute | Detail |
|---|---|
| **Repo** | [github.com/guinacio/mcp-google-workspace](https://github.com/guinacio/mcp-google-workspace) |
| **Stars** | 0 |
| **Maintenance** | Active, v0.3.12 released Aug 2026, 94 commits |
| **Language** | Python, FastMCP framework |
| **Published image** | **Yes:** `ghcr.io/guinacio/mcp-google-workspace:0.3.12` (signed, multi-arch `linux/amd64` + `linux/arm64`) |
| **Services covered** | Gmail, Calendar, Drive, Docs, Sheets, Tasks, People, Forms, Slides (+ optional Keep, Chat, Meet, Gemini behind feature flags) |
| **Transport** | STDIO (local) or Streamable HTTP (remote, authenticated) |

**Auth modes supported:**
1. **STDIO + desktop OAuth:** local single-user flow (like Claude Desktop).
2. **Streamable HTTP with OIDC JWT:** requires an external OIDC issuer (`MCP_HTTP_JWT_ISSUER`, `MCP_HTTP_JWKS_URI`, `MCP_HTTP_JWT_AUDIENCE`). Clients authenticate with a bearer JWT, then connect their Google account via `connect_google_workspace` → PKCE OAuth flow → per-user encrypted Google tokens stored in the server.

**How it maps to OWUI's existing wiring:**
- **Mismatch:** This server requires an OIDC bearer-token issuer — OWUI does not act as an OIDC issuer for tool servers. To use this, you'd need a separate OIDC IdP (Authelia? Keycloak?) to issue JWTs for the MCP server, adding a new dependency. The Streamable HTTP mode "refuses to start" without OIDC config. This is a **significant integration barrier** compared to Candidate 1.
- If OWUI's `auth_type: "none"` were used, the MCP server would reject unauthenticated requests (it requires a JWT).

**Tool-surface parity:** Equal coverage for the 4 target services. Notable strengths: `reply_email`/`reply_all_email` with RFC-compliant In-Reply-To headers, calendar conflict prevention with `idempotency_key`, progressive tool discovery (BM25 search to reduce context window).

### Candidate 3: rishapgandhi/google\_mcp

| Attribute | Detail |
|---|---|
| **Repo** | [github.com/rishapgandhi/google_mcp](https://github.com/rishapgandhi/google_mcp) |
| **Stars** | 2 |
| **Maintenance** | Minimal, v2.0.0 released June 2026, last push June 2026 |
| **Language** | Python, MCP SDK + google-api-python-client |
| **Published image** | No |
| **Services covered** | 10 services, 43 tools (Gmail, Calendar, Drive, Docs, Sheets, Slides, Forms, Tasks, Chat, Meet) |
| **Transport** | stdio only |
| **Auth** | Single-user desktop OAuth (saves `token.json` locally with `chmod 600`) |

**Verdict:** Not suitable. Stdio only (would need mcpo bridge to OWUI), no multi-user support, minimal maintenance. Listed for completeness.

---

## Option 2 — Direct REST API calls from Open WebUI Workspace Tools (Python)

### How it works

Open WebUI v0.11.1 Workspace Tools are Python scripts that run in-process on the server. They receive injected parameters including `__oauth_token__`:

> `__oauth_token__`: A dictionary containing the user's valid, automatically refreshed OAuth token payload. [...] The dictionary typically contains `access_token`, `id_token`, and other provider-specific data. — [Open WebUI Tools Development docs](https://docs.openwebui.com/features/extensibility/plugin/tools/development/)

The token is fetched via `get_system_oauth_token(request, user)` in [backend/open_webui/utils/middleware.py](https://github.com/open-webui/open-webui/blob/883f1dda/backend/open_webui/utils/middleware.py), which reads the `oauth_session_id` cookie and calls `request.app.state.oauth_manager.get_oauth_token(user_id, session_id)`. This auto-refreshes expired tokens using the stored `refresh_token` ([backend/open_webui/utils/oauth.py](https://github.com/open-webui/open-webui/blob/2b263550/backend/open_webui/utils/oauth.py)).

### Feasibility analysis

**Token access: YES.** Tools can access the user's OAuth access token via `__oauth_token__["access_token"]`. The token is automatically refreshed by OWUI's session manager before expiration.

**BUT — scope problem:** The current Google SSO configuration only requests `openid email profile` scopes ([docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md](docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md)). To get Gmail/Calendar/Docs/Sheets access tokens, the SSO scopes must be expanded to include:
- `https://www.googleapis.com/auth/gmail.readonly` (or `gmail.compose` for write)
- `https://www.googleapis.com/auth/calendar.events` (or `calendar.events.readonly`)
- `https://www.googleapis.com/auth/documents` (or `documents.readonly`)
- `https://www.googleapis.com/auth/spreadsheets` (or `spreadsheets.readonly`)
- `https://www.googleapis.com/auth/drive.file` (for file discovery)

This triggers Google's OAuth verification process for **sensitive scopes** ([Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes): `gmail.readonly` is "Sensitive"; [Docs API scopes](https://developers.google.com/workspace/docs/api/auth): `documents` is "Sensitive"; [Sheets API scopes](https://developers.google.com/workspace/sheets/api/scopes): `spreadsheets` is "Sensitive"). Sensitive scopes require Google's OAuth App Verification, which involves a security review process. For a personal/single-user app, this adds friction but is not a blocker — the "unsafe" consent warning already appears for the current setup.

### Effort estimate

| Component | Effort | Notes |
|---|---|---|
| Expand Google SSO scopes | 1 hour | Edit `GOOGLE_OAUTH_SCOPE` in `.env` / Docker Compose. All existing users will see a new consent screen. |
| Gmail tool (Python) | 4-8 hours | `search`, `read`, `send`, `list_threads`, `get_message`. Use `httpx` async client. Handle pagination, RFC 2822 encoding for sends. |
| Calendar tool (Python) | 4-6 hours | `list_events`, `search_events`, `create_event`, `update_event`, `delete_event`. Handle time zones, recurring events. |
| Docs tool (Python) | 2-4 hours | `get_document`, `create_document`, `batch_update_document`. Simpler surface (3 methods in REST API). |
| Sheets tool (Python) | 4-6 hours | `get_spreadsheet`, `get_values`, `update_values`, `batch_update`. A1 notation parsing, range handling. |
| Token refresh handling | Built-in | OWUI's `get_oauth_token` auto-refreshes. Tool just uses `__oauth_token__["access_token"]`. |
| Rate limits / quota | 2-4 hours | Gmail: 250 quota units/100s/user. Calendar: 300 queries/60s/user. Sheets: 300 requests/60s/user. Docs: 300 requests/60s/user. Need retry-with-backoff in each tool. |
| Testing | 4-8 hours | Unit tests with mocked HTTP, integration tests with real API. |
| **Total** | **~20-40 hours** | Conservative estimate for production-quality tools. |

### Key pitfalls

1. **OAuth scope expansion affects all SSO users.** Adding Workspace API scopes to the SSO consent screen changes what every user authorizes at login. This is acceptable for a single-user household but would be problematic in a multi-tenant deployment.
2. **No tool isolation from OWUI process.** Workspace Tools run in-process with Open WebUI. A slow Google API call blocks a worker thread. The async backend mitigates this but doesn't eliminate resource contention.
3. **Four separate code surfaces to maintain.** Each tool needs its own error handling, retry logic, rate-limit backoff, and schema definitions. Bug fixes in one don't propagate to others.
4. **Token expiration edge case.** Open issue [#20802](https://github.com/open-webui/open-webui/issues/20802) reports `__oauth_token__` can become `None` after a few hours in some deployments. The tool would need a fallback path when the token is unavailable.
5. **OAuth verification for sensitive scopes.** If the app is ever shared beyond test users, Google requires OAuth App Verification for `gmail.readonly`, `documents`, `spreadsheets` etc. — a multi-week review process.

---

## Comparison

| Criterion | Option 1: Self-hosted MCP (taylorwilsdon) | Option 2: OWUI Python Tools |
|---|---|---|
| **Developer Preview enrollment** | Not needed (wraps GA REST APIs) | Not needed (calls GA REST APIs directly) |
| **Control** | Full control of the server, own OAuth client, own container | Code lives in OWUI database, reviewed/managed via Admin UI |
| **Effort** | 2-4 hours: build container, add to compose, regenerate `TOOL_SERVER_CONNECTIONS` | 20-40 hours: write 4 Python tools, test, handle edge cases |
| **Auth burden** | Per-user OAuth consent (same as today), managed by MCP server | Expand SSO scopes (breaks existing consent for all users), OWUI handles token refresh |
| **Tool parity** | 120+ tools across 12 services, exceeds current 40-tool surface | Custom surface — only what you implement |
| **Maintenance** | Upstream repo updates; docker image rebuild | Own code to maintain, test, and update as Google API schemas evolve |
| **Multi-user** | Native OAuth 2.1 multi-user support | Works per-user via `__oauth_token__`, but token reliability has known issues |
| **Isolation** | Separate container, separate process, can scale independently | In-process with OWUI, shares CPU/RAM |
| **What changes in the repo** | Replace `gen-openwebui-mcp-connections.sh` to point at self-hosted server URL; update `docker-compose.sweetpaintedlady.yml` with new service; update `TOOL_SERVER_CONNECTIONS` JSON. Auth type likely changes to `"none"` if the MCP server handles its own OAuth. | Add `GOOGLE_OAUTH_SCOPE` entries to `.env.example` and compose; write 4 Python tool files under `services/agenticui/` or import from community; no compose changes for the server itself. |

### Concrete recommended path

1. **Deploy taylorwilsdon/google\_workspace\_mcp** as a new service in `docker-compose.sweetpaintedlady.yml`:
   ```yaml
   google-workspace-mcp:
     build:
       context: ./services/google-workspace-mcp  # cloned repo
       dockerfile: Dockerfile
     ports:
       - "127.0.0.1:8002:8000"  # or Tailscale IP
     environment:
       - MCP_ENABLE_OAUTH21=true
       - GOOGLE_OAUTH_CLIENT_ID=${GOOGLE_MCP_CLIENT_ID}
       - GOOGLE_OAUTH_CLIENT_SECRET=${GOOGLE_MCP_CLIENT_SECRET}
       - WORKSPACE_EXTERNAL_URL=https://agentic.overachieverlabs.com/mcp
     volumes:
       - mcp-credentials:/app/.credentials
   ```

2. **Update `gen-openwebui-mcp-connections.sh`** to generate a single `TOOL_SERVER_CONNECTIONS` entry pointing at `http://google-workspace-mcp:8000/mcp` with `auth_type: "none"` (since the MCP server handles its own OAuth) — or `auth_type: "oauth_2.1"` if OWUI's OAuth manager can be wired to the server's metadata endpoint (requires testing).

3. **First-deploy user flow** remains the same: user visits the OAuth authorize URL, consents to scopes, tokens are stored. The MCP server manages its own token storage and refresh.

4. **Retire the Developer Preview dependency** entirely. Remove `gmailmcp.googleapis.com`, `calendarmcp.googleapis.com`, `docsmcp.googleapis.com`, `sheetsmcp.googleapis.com` from the enabled GCP services (they're no longer needed). Keep the base API enables (`gmail.googleapis.com`, `calendar-json.googleapis.com`, `docs.googleapis.com`, `sheets.googleapis.com`, `drive.googleapis.com`).

---

## Sources

| Claim | Source |
|---|---|
| Developer Preview program requires Workspace email + application form | [developers.google.com/workspace/preview](https://developers.google.com/workspace/preview) |
| MCP servers are part of Developer Preview | [developers.google.com/workspace/preview](https://developers.google.com/workspace/preview) — "MCP SERVERS" section listing all 8 MCP servers |
| Gmail API is GA ("publicly available") | [Gmail API release notes](https://developers.google.com/workspace/gmail/release-notes) — "The Gmail API is publicly available!" |
| Gmail API endpoint + REST methods | [Gmail API reference](https://developers.google.com/workspace/gmail/api/reference/rest) — `gmail.googleapis.com` |
| Calendar API is GA, RESTful | [Calendar API overview](https://developers.google.com/workspace/calendar/api/guides/overview), [Calendar API reference](https://developers.google.com/workspace/calendar/api/v3/reference) — `www.googleapis.com/calendar/v3` |
| Sheets API is GA, RESTful | [Sheets API overview](https://developers.google.com/workspace/sheets/api/guides/concepts), [Sheets API reference](https://developers.google.com/workspace/sheets/api/reference/rest) — `sheets.googleapis.com` |
| Docs API is GA | [Docs API release notes](https://developers.google.com/docs/docs/release-notes) — "The Google Docs API is now generally available" |
| Drive API is GA | [Drive API release notes](https://developers.google.com/workspace/drive/release-notes) — "The Google Drive API is now generally available" |
| OAuth 2.0 bearer token auth for all Google APIs | [Using OAuth 2.0 to Access Google APIs](https://developers.google.com/identity/protocols/oauth2) |
| Gmail API scopes (sensitive) | [Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes) |
| Calendar API scopes | [Calendar API scopes](https://developers.google.com/workspace/calendar/api/auth) |
| Docs API scopes (sensitive) | [Docs API scopes](https://developers.google.com/workspace/docs/api/auth) |
| Sheets API scopes (sensitive) | [Sheets API scopes](https://developers.google.com/workspace/sheets/api/scopes) |
| taylorwilsdon/google\_workspace\_mcp repo, features, auth modes | [GitHub repo](https://github.com/taylorwilsdon/google_workspace_mcp), [Advanced Deployment docs](https://workspacemcp.com/docs) |
| guinacio/mcp-google-workspace repo, Docker image, auth modes | [GitHub repo](https://github.com/guinacio/mcp-google-workspace), [Releases page](https://github.com/guinacio/mcp-google-workspace/releases) (v0.3.12, GHCR image) |
| rishapgandhi/google\_mcp repo | [GitHub repo](https://github.com/rishapgandhi/google_mcp) |
| OWUI `__oauth_token__` injection in tools | [Tools Development docs](https://docs.openwebui.com/features/extensibility/plugin/tools/development/) |
| OWUI `get_system_oauth_token` implementation | [middleware.py](https://github.com/open-webui/open-webui/blob/883f1dda/backend/open_webui/utils/middleware.py) |
| OWUI OAuth session management + auto-refresh | [oauth.py](https://github.com/open-webui/open-webui/blob/2b263550/backend/open_webui/utils/oauth.py) |
| OWUI `oauth_session` table schema | [oauth_sessions.py](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/models/oauth_sessions.py) |
| OWUI `__oauth_token__` can become `None` (open issue) | [Issue #20802](https://github.com/open-webui/open-webui/issues/20802) |
| Current `TOOL_SERVER_CONNECTIONS` generation | [scripts/gen-openwebui-mcp-connections.sh](scripts/gen-openwebui-mcp-connections.sh) |
| Current SSO scopes = `openid email profile` | [2026-09-12 design doc](docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md) |
| Google API quota limits (Gmail 250/100s, Calendar 300/60s, Sheets 300/60s, Docs 300/60s) | **Unverified** — commonly cited figures, not found in primary Google docs during this research. Needs confirmation from [Google Workspace quota docs](https://developers.google.com/workspace/gmail/api/quotas). |

## Unverified claims

1. **Google API quota numbers** (Gmail 250 quota units/100s/user, Calendar 300 queries/60s/user, Sheets 300 requests/60s/user, Docs 300 requests/60s/user) — widely cited but not confirmed against current Google docs during this research session.
2. **Whether OWUI's `oauth_2.1` auth type can discover OAuth metadata from a self-hosted MCP server** (i.e., whether the self-hosted server needs to expose `/.well-known/oauth-authorization-server` for OWUI's `get_oauth_client_info_with_static_credentials` to work) — requires testing. If not, `auth_type: "none"` is the fallback.
3. **Whether taylorwilsdon/google\_workspace\_mcp's OAuth 2.1 mode exposes an OIDC-compatible metadata endpoint** that OWUI's OAuth manager can consume — not verified from the source code. The server's auth docs describe bearer-token validation but not a standard OIDC discovery endpoint.
4. **Open issue #20802** (`__oauth_token__` becomes `None` after a few hours) — confirmed as reported, but the root cause and fix status are unclear from the issue alone.
