# Open WebUI Google Workspace Access — Research Findings

**Date:** 2026-09-12
**Scope:** Gmail, Calendar, Docs/Sheets access via Open WebUI; multi-account support
**Method:** Primary sources only — Open WebUI source code, official docs, Google Identity docs, Google Workspace MCP server docs

---

## Summary

1. **Open WebUI has NO native Gmail/Calendar/Docs/Sheeds API access.** Its Google OAuth (`GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`) is auth-only (SSO login). The OAuth tokens are stored server-side for session management but are **not exposed to tools/functions** for downstream Google API calls. The Google-specific OAuth flow in Open WebUI requests only `openid email profile` scopes by default — insufficient for any Workspace API.

2. **The working path is Google's official remote MCP servers** (Developer Preview, `gmailmcp.googleapis.com`, `calendarmcp.googleapis.com`, etc.) connected as MCP tool servers in Open WebUI v0.6.31+. Each service gets its own MCP endpoint; Open WebUI's MCP integration supports OAuth 2.1 per-user auth with automatic token refresh.

3. **`TOOL_SERVER_CONNECTIONS` env var** exists in `backend/open_webui/config.py` and accepts a JSON array of tool server configs. With `ENABLE_PERSISTENT_CONFIG=False`, env vars are authoritative every boot, so this can be set declaratively in Docker Compose.

4. **Multi-account: one Google OAuth client (one GCP project) serves unlimited Google identities.** Each user gets their own refresh token. The 100-refresh-token limit is *per Google Account per client ID*, so one user can have 100 tokens across 100 apps, not 100 users total. Open WebUI's MCP OAuth model is per-user — each Open WebUI user authorizes independently and tokens are stored per `(user_id, provider)` in the `oauth_sessions` table.

5. **For a single user with 2+ Google accounts** (personal + work), the bottleneck is that Open WebUI's built-in Google OAuth (SSO) only supports ONE `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` pair. The MCP tool server OAuth flow is also one client per connection. Workarounds: (a) run two MCP server instances with different OAuth clients, (b) use a community MCP server with multi-account support, or (c) one GCP project with both accounts authorized under the same OAuth client (the MCP server can only act on one account per OAuth session, so you'd need two separate MCP connections).

---

## 1. Built-in Google Integration — Auth Only, Not API Access

### OAuth env vars are for SSO login only

Open WebUI's Google OAuth configuration (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_OAUTH_SCOPE`) exists solely for user authentication (SSO). The default scope is `openid email profile` — these are OIDC identity scopes, not Google Workspace API scopes.

- **Source:** [Open WebUI env configuration docs](https://docs.openwebui.com/reference/env-configuration) — `GOOGLE_OAUTH_SCOPE` defaults to `openid email profile`
- **Source:** [Open WebUI SSO docs](https://docs.openwebui.com/features/authentication-access/auth/sso) — Google section describes login flow, redirect URI `<open-webui>/oauth/google/callback`

### Token storage: server-side but not reusable for Google API calls

Open WebUI stores OAuth tokens (access_token, refresh_token, id_token) encrypted in its database via the `oauth_sessions` table. The backend has automatic token refresh logic (`get_oauth_token`, `_refresh_token` in `backend/open_webui/utils/oauth.py`). However, this infrastructure is designed for:
- Validating the user's Open WebUI session
- Forwarding tokens to downstream OpenAI-compatible API endpoints (when configured)
- Token exchange for external apps

**The tokens are NOT exposed to Python tools/functions or made available as credentials for calling Google Workspace APIs.** Tracing through `backend/open_webui/utils/oauth.py` (2286 lines): the `get_oauth_token` method returns tokens to internal session middleware, not to any tool execution context.

- **Verified in source:** [oauth.py get_oauth_token](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/utils/oauth.py) — returns `session.token` to session middleware, no tool-facing exposure

### No native Google Workspace tools

Searching the Open WebUI repo for gmail/calendar/drive/google_api reveals:
- `ENABLE_GOOGLE_DRIVE_INTEGRATION` + `GOOGLE_DRIVE_CLIENT_ID` + `GOOGLE_DRIVE_API_KEY` — these enable a **file picker** for uploading files from Google Drive into the RAG knowledge base, not API access to read/send emails, manage calendars, or edit docs.
- No Python tools or functions in the repo call Gmail API, Calendar API, or Drive API for read/write operations.

- **Source:** [config.py GOOGLE_DRIVE lines](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/config.py) — `ENABLE_GOOGLE_DRIVE_INTEGRATION` gate
- **Conclusion:** Open WebUI has zero native Google Workspace tool integration beyond file import.

---

## 2. Tools/MCP Plugin Ecosystem

### MCP support (v0.6.31+)

Open WebUI natively supports MCP (Model Context Protocol) via Streamable HTTP transport. Configuration is via:
- **Admin UI:** Settings > Admin > Integrations > External Tool Servers > Add Connection > Type: MCP (Streamable HTTP)
- **Env var:** `TOOL_SERVER_CONNECTIONS` — JSON array parsed in `backend/open_webui/config.py`

- **Source:** [Open WebUI MCP docs](https://docs.openwebui.com/features/extensibility/mcp)
- **Source:** [config.py TOOL_SERVER_CONNECTIONS](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/config.py) — `tool_server_connections = JSONCodec.loads(os.getenv('TOOL_SERVER_CONNECTIONS', '[]'))`

### TOOL_SERVER_CONNECTIONS format

From the source code, each entry in the JSON array is a `ToolServerConnection` with fields like:
```json
{
  "type": "mcp",
  "url": "https://gmailmcp.googleapis.com/mcp/v1",
  "auth_type": "oauth_2.1_static",
  "info": {
    "id": "google-gmail",
    "name": "Google Gmail",
    "oauth_client_id": "...",
    "oauth_client_secret": "...",
    "oauth_client_info": "<encrypted blob>"
  }
}
```

With `ENABLE_PERSISTENT_CONFIG=False`, the env var is read directly at startup, so this can be set declaratively. The stored `oauth_client_info` is an encrypted blob (Fernet-encrypted via `OAUTH_SESSION_TOKEN_ENCRYPTION_KEY`/`WEBUI_SECRET_KEY`), which makes pure env-var setup awkward — you'd need to either:
1. Pre-generate the encrypted blob, or
2. Configure via Admin UI once, then the database persists it (but with `ENABLE_PERSISTENT_CONFIG=False`, the env var would override on next boot)

**Important caveat:** The `oauth_client_info` field is an encrypted JSON blob created during the "Register Client" flow in the Admin UI. Setting this purely via env var requires pre-encrypting the data with the same `WEBUI_SECRET_KEY`. This is not documented and may be impractical for as-code deployments.

- **Verified in source:** [oauth.py encrypt_data/decrypt_data](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/utils/oauth.py) — uses Fernet with `OAUTH_CLIENT_INFO_ENCRYPTION_KEY`
- **Verified in source:** [config.py TOOL_SERVER_CONNECTIONS parsing](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/config.py)

### OpenAPI as alternative

Open WebUI also supports OpenAPI tool servers (type: `openapi`). The community MCP server `mcpo` (from open-webui/mcpo) can translate stdio/SSE MCP servers into OpenAPI endpoints. This is a viable path if the Google MCP server doesn't work with Streamable HTTP.

- **Source:** [open-webui/mcpo](https://github.com/open-webui/mcpo)

### Google's official MCP servers (PRIMARY SOURCE — OWNED BY GOOGLE)

Google Workspace offers **official remote MCP servers** for each product, at `developers.google.com`. These are Developer Preview (as of 2026-09). Each has its own endpoint:

| Service | MCP Endpoint |
|---------|-------------|
| Gmail | `https://gmailmcp.googleapis.com/mcp/v1` |
| Google Drive | `https://drivemcp.googleapis.com/mcp/v1` |
| Google Docs | `https://docsmcp.googleapis.com/mcp/v1` |
| Google Sheets | `https://sheetsmcp.googleapis.com/mcp/v1` |
| Google Slides | `https://slidesmcp.googleapis.com/mcp/v1` |
| Google Calendar | `https://calendarmcp.googleapis.com/mcp/v1` |
| Google Chat | `https://chatmcp.googleapis.com/mcp/v1` |
| People API | `https://people.googleapis.com/mcp/v1` |

- **Source:** [Configure Google Workspace MCP servers](https://developers.google.com/workspace/guides/configure-mcp-servers) (developers.google.com — official Google docs)
- **Source:** [Gmail MCP reference](https://developers.google.com/workspace/gmail/api/reference/mcp)
- **Source:** [Calendar MCP reference](https://developers.google.com/workspace/calendar/api/v3/reference/mcp)
- **Source:** [Drive MCP reference](https://developers.google.com/workspace/drive/api/reference/mcp)
- **Source:** [Docs MCP reference](https://developers.google.com/workspace/docs/api/reference/mcp)

**Required GCP setup per Google docs:**
1. Enable the base APIs: `gmail.googleapis.com`, `drive.googleapis.com`, `docs.googleapis.com`, `sheets.googleapis.com`, `calendar-json.googleapis.com`, etc.
2. Enable the MCP services: `gmailmcp.googleapis.com`, `drivemcp.googleapis.com`, `docsmcp.googleapis.com`, `sheetsmcp.googleapis.com`, `calendarmcp.googleapis.com`, etc.
3. Configure OAuth consent screen with appropriate scopes
4. Create OAuth 2.0 client ID (Web application type)
5. Redirect URI for Open WebUI: `<WEBUI_URL>/oauth/clients/mcp:<server_id>/callback` (derived from Open WebUI's MCP OAuth callback pattern)

**Required OAuth scopes (per Google MCP docs):**
- Gmail: `gmail.readonly`, `gmail.compose`
- Calendar: `calendar.calendarlist.readonly`, `calendar.events.freebusy`, `calendar.events.readonly`
- Drive: `drive.readonly`, `drive.file`
- Docs: `drive.readonly`, `drive.file`, `documents.readonly`, `documents`
- Sheets: `drive.readonly`, `drive.file`, `spreadsheets.readonly`, `spreadsheets`

### Community MCP servers (NOT official — labeled as community)

Several third-party Google Workspace MCP servers exist:

| Repo | Stars | Language | Notes |
|------|-------|----------|-------|
| [taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp) | ~3100 | Python | Most popular; supports OAuth 2.1, stateless mode, 12 services |
| [dguido/google-workspace-mcp](https://github.com/dguido/google-workspace-mcp) | ~38 | TypeScript | npm package `@dguido/google-workspace-mcp` |
| [ngs/google-mcp-server](https://github.com/ngs/google-mcp-server) | ~2 | Go | Explicit multi-account support, per-account config |
| [IntegriGit/google_workspace_mcp](https://github.com/IntegriGit/google_workspace_mcp) | ~1 | Python | Similar to taylorwilsdon |

These are **community projects**, not Google-owned. They run as stdio servers and would need `mcpo` to bridge to Open WebUI's Streamable HTTP requirement (or OpenAPI translation).

---

## 3. OAuth Per-Account Mechanics

### Single Google account flow (per Google Identity docs)

1. Create a Google Cloud project
2. Configure OAuth consent screen (Internal or External)
3. Add scopes manually (gmail.readonly, calendar.readonly, etc.)
4. Create OAuth 2.0 client ID (Web application type)
5. Add authorized redirect URIs
6. User authorizes via Google consent screen with `access_type=offline` (or `prompt=consent` for forced re-consent)
7. Google returns auth code → exchange for access_token + refresh_token
8. Store refresh_token securely; use it to refresh access_token when expired

- **Source:** [Using OAuth 2.0 for Web Server Applications](https://developers.google.com/identity/protocols/oauth2/web-server)
- **Source:** [OAuth 2.0 scopes](https://developers.google.com/identity/protocols/oauth2/scopes)

### Multiple Google identities, ONE OAuth client — VERIFIED YES

Google explicitly supports one OAuth client (one GCP project) serving **any number of Google identities**. Each user who consents gets their own refresh token. The documented limit is **100 refresh tokens per Google Account per OAuth client ID** (a single user can authorize 100 different apps with the same client; exceeding this invalidates the oldest). This does NOT limit the number of distinct users.

- **Source:** [OAuth 2.0 overview](https://developers.google.com/identity/protocols/oauth2) — "There is currently a limit of 100 refresh tokens per Google Account per OAuth 2.0 client ID"
- **Source:** [Google Developer Forum discussion](https://discuss.google.dev/t/regarding-google-oauth-and-scaling-web-application/125895) — confirmed by Google: "The limit is per user, meaning you can have thousands of users but each user can only have up to 100 refresh token per client ID"

### What Open WebUI supports

Open WebUI's Google OAuth config accepts **one** `GOOGLE_CLIENT_ID` and **one** `GOOGLE_CLIENT_SECRET`. This means:
- One OAuth client = one GCP project
- Any Google identity can authorize through it (if consent screen is set to External or includes them)
- Each Open WebUI user gets their own OAuth session and refresh token

For MCP tool servers, the same pattern holds: one MCP connection = one OAuth client. Open WebUI stores OAuth tokens per `(user_id, provider)` where provider is `mcp:<server_id>`.

### Multiple Google accounts for ONE user (personal + work)

This is the harder problem. A single Open WebUI user wants both `personal@gmail.com` and `work@company.com` accessible:

**Option A: Two MCP connections, same OAuth client, different sessions**
- Add Gmail MCP server twice (different `info.id` values)
- User authorizes once for personal account, once for work account
- Both use the same `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`
- Problem: Google's consent screen may default to the same account; user needs `prompt=select_account` to pick

**Option B: Two separate OAuth clients (two GCP projects)**
- More administrative overhead
- Each MCP connection uses its own client ID/secret

**Option C: Community MCP server with multi-account support**
- [ngs/google-mcp-server](https://github.com/ngs/google-mcp-server) (Go) has explicit multi-account support with per-account config and `*_list_all_accounts` tools
- Would need mcpo bridge to Open WebUI

---

## 4. Minimal Path for This Stack

### Prerequisites
- Open WebUI version ≥ v0.6.31 (verify current agenticui image tag)
- `WEBUI_SECRET_KEY` set (required for OAuth token encryption)
- `ENABLE_PERSISTENT_CONFIG=False` (already set per repo context)

### Step 1: Google Cloud Project Setup

1. Create a GCP project (or use existing)
2. Enable APIs:
   ```
   gcloud services enable gmail.googleapis.com drive.googleapis.com \
     docs.googleapis.com sheets.googleapis.com calendar-json.googleapis.com \
     gmailmcp.googleapis.com drivemcp.googleapis.com docsmcp.googleapis.com \
     sheetsmcp.googleapis.com calendarmcp.googleapis.com
   ```
3. Configure OAuth consent screen (External, add test users)
4. Add scopes:
   - `https://www.googleapis.com/auth/gmail.readonly`
   - `https://www.googleapis.com/auth/calendar.events.readonly`
   - `https://www.googleapis.com/auth/drive.readonly`
   - `https://www.googleapis.com/auth/documents.readonly`
   - `https://www.googleapis.com/auth/spreadsheets.readonly`
5. Create OAuth 2.0 client ID (Web application)
6. Add redirect URI: `https://<YOUR_WEBUI_URL>/oauth/clients/mcp:google-gmail/callback` (one per MCP connection)

### Step 2: Docker Compose Changes

Add env vars to the agenticui service:
```yaml
environment:
  - WEBUI_SECRET_KEY=<existing-or-new-key>
  - ENABLE_PERSISTENT_CONFIG=False
```

**Note:** `TOOL_SERVER_CONNECTIONS` is parsed at startup from env, but the `oauth_client_info` field requires Fernet-encrypted data. The practical approach is:
1. Start the container without tool server config
2. Configure MCP connections via Admin UI (Settings > Admin > Integrations)
3. The database stores the encrypted blobs
4. On subsequent boots, `ENABLE_PERSISTENT_CONFIG=False` means env vars take precedence, but the tool server connections are also read from the DB via `Config.get('tool_server.connections')` — there may be a precedence conflict. **This needs testing.**

### Step 3: Admin UI Configuration

For each Google service (Gmail, Calendar, Docs, Sheets), add an MCP connection:
- Type: MCP (Streamable HTTP)
- URL: `https://gmailmcp.googleapis.com/mcp/v1` (etc.)
- Auth: OAuth 2.1 (Static)
- Client ID/Secret: from GCP project
- Register Client → Save → Authorize OAuth (browser redirect to Google consent)

### Step 4: Extending to 2+ Google Accounts

For a single Open WebUI user with personal + work Google accounts:

**Recommended approach: Two MCP connections per service**
- `gmail-personal` → URL `https://gmailmcp.googleapis.com/mcp/v1` → authorize as personal@gmail.com
- `gmail-work` → URL `https://gmailmcp.googleapis.com/mcp/v1` → authorize as work@company.com (use `prompt=select_account` in OAuth params)
- Both share the same OAuth client ID/secret

This requires the OAuth consent flow to support `select_account`. Check if Open WebUI's MCP OAuth flow supports custom authorize params — the docs show `GOOGLE_OAUTH_AUTHORIZE_PARAMS` for the SSO flow but I could not verify an equivalent for MCP tool server OAuth.

**Alternative: Community MCP with multi-account**
- Deploy [ngs/google-mcp-server](https://github.com/ngs/google-mcp-server) as a sidecar
- Configure it with one OAuth client and multiple account tokens
- Bridge to Open WebUI via mcpo or OpenAPI
- This server has `*_list_all_accounts` tools that query across all configured accounts

---

## Open Questions / Unverified Claims

1. **TOOL_SERVER_CONNECTIONS precedence with ENABLE_PERSISTENT_CONFIG=False**: The env var is parsed at module load time in `config.py`, but tool server connections are also stored in the DB at `tool_server.connections`. I could not verify which takes precedence at runtime when persistent config is disabled. **Needs testing on a dev instance.**

2. **Pre-generating oauth_client_info encrypted blob**: The Fernet encryption uses `OAUTH_CLIENT_INFO_ENCRYPTION_KEY` (derived from `WEBUI_SECRET_KEY`). I could not find a CLI or script to pre-generate this blob for as-code deployment. The Admin UI's "Register Client" button performs the dynamic client registration or static credential setup and stores the encrypted result. **Pure env-var setup for MCP OAuth may not be practical.**

3. **Custom OAuth authorize params for MCP connections**: Open WebUI's SSO flow supports `GOOGLE_OAUTH_AUTHORIZE_PARAMS` (JSON with `prompt`, `login_hint`, `hd`). I could not find an equivalent for MCP tool server OAuth flows. Setting `prompt=select_account` would be needed for multi-account flows. **Needs source code verification.**

4. **Google Workspace MCP servers — Developer Preview status**: The official Google MCP servers are marked "Developer Preview" which means they may change, have limited SLAs, or require allowlisting. Not verified whether they're GA or still in preview as of 2026-09.

5. **Open WebUI version on the current agenticui deployment**: Not verified. MCP support requires v0.6.31+.

6. **Whether the official Google MCP servers support `oauth_2.1_static` or require DCR (Dynamic Client Registration)**: The Google docs show config with client ID/secret for Antigravity and Claude, suggesting static credentials work. But Open WebUI's OAuth discovery flow may behave differently with Google's endpoints. **Needs testing.**

7. **Multi-account with official Google MCP servers**: Not verified whether two separate MCP connections to `gmailmcp.googleapis.com/mcp/v1` with the same OAuth client but different user sessions would correctly route to different Google accounts. Google's OAuth consent flow uses browser cookies to determine the signed-in account, which could cause both connections to authorize the same account unless `prompt=select_account` is used.

## Env-persistence verification (2026-09-12 follow-up)

### 1. `TOOL_SERVER_CONNECTIONS` env var — definition, schema, PersistentConfig?

**File:** `backend/open_webui/config.py` ([source](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/config.py))

```python
try:
    tool_server_connections = JSONCodec.loads(os.getenv('TOOL_SERVER_CONNECTIONS', '[]'))
except Exception as e:
    log.exception(f'Error loading TOOL_SERVER_CONNECTIONS: {e}')
    tool_server_connections = []

TOOL_SERVER_CONNECTIONS = tool_server_connections
```

**Not a PersistentConfig.** It is a plain module-level variable read at import time from the env var. It is NOT stored in or read from the `config` table.

**Pydantic model** (used by the Admin API router, `backend/open_webui/routers/configs.py` ([source](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/routers/configs.py))):

```python
class ToolServerConnection(BaseModel):
    url: str
    path: str
    type: str | None = 'openapi'  # openapi, mcp
    auth_type: str | None
    headers: dict | str | None = None
    key: str | None
    config: dict | None
    info: dict | None = None
    model_config = ConfigDict(extra='allow')
```

The `info` dict carries `id`, `name`, `oauth_client_id`, `oauth_client_secret`, `oauth_client_info` (encrypted blob), `oauth_scope`, `oauth_server_url`, `oauth_resource_parameter`. With `extra='allow'`, any extra fields pass through.

When loaded from env, all fields are accepted as-is (JSON → dict). No validation or transformation is applied at the env-parsing layer; validation only happens when the Admin API deserializes into `ToolServerConnection`.

### 2. `oauth_client_info` encryption — mechanism, key, offline viability

**File:** `backend/open_webui/utils/oauth.py` ([source](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/utils/oauth.py))

```python
OAUTH_CLIENT_INFO_ENCRYPTION_KEY = os.getenv('OAUTH_CLIENT_INFO_ENCRYPTION_KEY', WEBUI_SECRET_KEY)

if len(OAUTH_CLIENT_INFO_ENCRYPTION_KEY) != 44:
    key_bytes = hashlib.sha256(OAUTH_CLIENT_INFO_ENCRYPTION_KEY.encode()).digest()
    OAUTH_CLIENT_INFO_ENCRYPTION_KEY = base64.urlsafe_b64encode(key_bytes)
else:
    OAUTH_CLIENT_INFO_ENCRYPTION_KEY = OAUTH_CLIENT_INFO_ENCRYPTION_KEY.encode()

FERNET = Fernet(OAUTH_CLIENT_INFO_ENCRYPTION_KEY)

def encrypt_data(data) -> str:
    data_json = JSONCodec.dumps(data)
    encrypted = FERNET.encrypt(data_json.encode()).decode()
    return encrypted

def decrypt_data(data: str):
    decrypted = FERNET.decrypt(data.encode()).decode()
    return JSONCodec.loads(decrypted)
```

**Key:** Derived from `OAUTH_CLIENT_INFO_ENCRYPTION_KEY` env var, defaulting to `WEBUI_SECRET_KEY`. If the key is not already 44 chars (a Fernet-compatible base64 string), it is SHA-256 hashed and base64-encoded.

**Encrypted format:** The plaintext is a JSON serialization of `OAuthClientInformationFull.model_dump(mode='json')`, which includes:

```python
class OAuthClientInformationFull(OAuthClientMetadata):
    issuer: Optional[str] = None
    resource: Optional[str] = None
    oauth_resource_parameter: OAuthResourceParameterMode = 'auto'
    client_id: str
    client_secret: str | None = None
    client_id_issued_at: int | None = None
    client_secret_expires_at: int | None = None
    server_metadata: Optional[OAuthMetadata] = None
    # + inherited from OAuthClientMetadata:
    client_name, redirect_uris, grant_types, response_types, scope,
    token_endpoint_auth_method, etc.
```

**Can a pre-encrypted blob work via env JSON?** YES — if you encrypt the exact same JSON structure with the same `WEBUI_SECRET_KEY` (or `OAUTH_CLIENT_INFO_ENCRYPTION_KEY`) using Fernet, and supply it as the `oauth_client_info` field in the `TOOL_SERVER_CONNECTIONS` JSON, it will decrypt correctly at runtime. The `resolve_oauth_client_info()` function calls `decrypt_data(info.get('oauth_client_info', ''))` when loading connections.

### 3. Static OAuth client credentials — pre-registered client_id/secret support

**File:** `backend/open_webui/routers/configs.py` ([source](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/routers/configs.py))

The `POST /api/v1/configs/oauth/clients/register` endpoint accepts:

```python
class OAuthClientRegistrationForm(BaseModel):
    url: str
    client_id: str
    client_name: str | None = None
    client_secret: str | None = None
    oauth_server_url: str | None = None
    oauth_scope: str | None = None
```

When `client_secret` is provided, the endpoint calls `get_oauth_client_info_with_static_credentials()` (in `oauth.py`) instead of dynamic registration. This function builds an `OAuthClientInformationFull` from the provided `client_id`/`client_secret` + discovery metadata, skipping DCR entirely.

The endpoint then returns `{'status': True, 'oauth_client_info': encrypt_data(oauth_client_info.model_dump(mode='json'))}` — i.e., it accepts cleartext credentials and encrypts them server-side.

For `auth_type: oauth_2.1_static`, the `resolve_oauth_client_info()` function overlays `info.oauth_client_id` and `info.oauth_client_secret` onto the decrypted `oauth_client_info` blob at runtime:

```python
def resolve_oauth_client_info(connection: dict) -> dict:
    info = connection.get('info') or {}
    data = decrypt_data(info.get('oauth_client_info', ''))
    if connection.get('auth_type') == 'oauth_2.1_static':
        if info.get('oauth_client_id') and info.get('oauth_client_secret'):
            data['client_id'] = info['oauth_client_id']
            data['client_secret'] = info['oauth_client_secret']
    return data
```

This means static creds can be supplied EITHER inside the encrypted blob OR as separate cleartext fields in `info`.

### 4. Token storage after OAuth handshake — per-user? DB-stored? Independent of `ENABLE_PERSISTENT_CONFIG`?

**File:** `backend/open_webui/models/oauth_sessions.py` ([source](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/models/oauth_sessions.py))

The `oauth_session` table stores:

```python
class OAuthSession(Base):
    __tablename__ = 'oauth_session'
    id = Column(Text, primary_key=True)
    user_id = Column(Text, nullable=False)
    provider = Column(Text, nullable=False)  # e.g. 'mcp:google-gmail'
    token = Column(Text, nullable=False)      # Fernet-encrypted JSON
    expires_at = Column(BigInteger, nullable=False)
    created_at = Column(BigInteger, nullable=False)
    updated_at = Column(BigInteger, nullable=False)
```

- **Per-user:** YES — indexed by `(user_id, provider)` composite.
- **Token encryption:** Uses `OAUTH_SESSION_TOKEN_ENCRYPTION_KEY` (separate from `OAUTH_CLIENT_INFO_ENCRYPTION_KEY`, but also defaults to `WEBUI_SECRET_KEY`).
- **Persists in DB across restarts:** YES — this is a regular SQLAlchemy table, not affected by `ENABLE_PERSISTENT_CONFIG`.
- **Independent of `ENABLE_PERSISTENT_CONFIG`:** YES — `ENABLE_PERSISTENT_CONFIG` only gates the `config` table via `Config.persistent_enabled_for()`. The `oauth_sessions` table has its own separate flag: `ENABLE_OAUTH_PERSISTENT_CONFIG` (which controls whether `oauth.*` keys in the `config` table are DB-authoritative, NOT the `oauth_session` table). The `oauth_session` table is ALWAYS used for token storage regardless of either flag.

**What `ENABLE_PERSISTENT_CONFIG` actually gates** (`backend/open_webui/models/config.py`):

```python
class Config(Base):
    PERSISTENT_ENABLED: ClassVar[bool] = True
    OAUTH_PERSISTENT_ENABLED: ClassVar[bool] = False

    @classmethod
    def persistent_enabled_for(cls, key: str) -> bool:
        if not cls.PERSISTENT_ENABLED:
            return False
        if key.startswith('oauth.') and not cls.OAUTH_PERSISTENT_ENABLED:
            return False
        return True
```

When `ENABLE_PERSISTENT_CONFIG=False`, `Config.get()`, `Config.get_many()`, `Config.get_namespace()` all skip the DB and return defaults from `Config.DEFAULTS` (populated from env vars at module load time). The `config` table is not read or written.

### 5. Per-key exemption from `ENABLE_PERSISTENT_CONFIG=False`

**File:** `backend/open_webui/models/config.py`

```python
@classmethod
def persistent_enabled_for(cls, key: str) -> bool:
    if not cls.PERSISTENT_ENABLED:
        return False
    if key.startswith('oauth.') and not cls.OAUTH_PERSISTENT_ENABLED:
        return False
    return True
```

**No per-key whitelist exists.** The only special case is: when `ENABLE_PERSISTENT_CONFIG=True` but `ENABLE_OAUTH_PERSISTENT_CONFIG=False`, keys starting with `oauth.` are treated as non-persistent (env-authoritative). There is NO mechanism to exempt specific non-oauth keys (like `tool_server.connections`) from the global `ENABLE_PERSISTENT_CONFIG` flag. All non-oauth keys are either ALL persistent or ALL env-authoritative.

### 6. Precedence: env var connections vs DB connections with `ENABLE_PERSISTENT_CONFIG=False`

**CRITICAL FINDING: `TOOL_SERVER_CONNECTIONS` env var and DB connections are on SEPARATE rails.**

- `TOOL_SERVER_CONNECTIONS` (module-level in `config.py`) is read from the env var at import time. It is NOT stored in the `config` table and NOT affected by `ENABLE_PERSISTENT_CONFIG`.
- `Config.get('tool_server.connections')` reads from the `config` table (the Admin UI's storage path). With `ENABLE_PERSISTENT_CONFIG=False`, this returns the default value (`[]`).

**They do NOT merge.** They do NOT conflict. They are completely independent:

- The `OAuthClientManager.ensure_client_from_config()` method (in `oauth.py`) reads from `Config.get('tool_server.connections')` — the DB path, NOT the env var.
- The `set_tool_servers()` function (in `utils/tools.py`) is what reads `TOOL_SERVER_CONNECTIONS` from the module-level env var and activates those connections.

**So with `ENABLE_PERSISTENT_CONFIG=False`:**
- Env-defined connections via `TOOL_SERVER_CONNECTIONS` → activated via `set_tool_servers()` at startup.
- DB-defined connections → ignored (Config returns defaults).
- No merging occurs.

### 7. MCP OAuth authorize params — `prompt=select_account` support

**Files:** 
- `backend/open_webui/utils/oauth.py` — `OAuthClientManager.handle_authorize()` ([source](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/utils/oauth.py))
- `backend/open_webui/config.py` — `OAUTH_AUTHORIZE_PARAMS` and `GOOGLE_OAUTH_AUTHORIZE_PARAMS` ([source](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/config.py))

The MCP OAuth authorize handler:

```python
async def handle_authorize(self, request, client_id: str, user_id: str) -> RedirectResponse:
    ...
    kwargs = build_oauth_request_params(client_info)  # only scope, resource
    auth_data = await client.create_authorization_url(redirect_uri_str, **kwargs)
```

**`OAUTH_AUTHORIZE_PARAMS`** (generic OAuth SSO) and **`GOOGLE_OAUTH_AUTHORIZE_PARAMS`** (Google SSO) are applied only in the SSO login OAuth flow, NOT in the MCP tool server OAuth flow. The `build_oauth_request_params()` function only produces `scope` and `resource` — there is no `authorize_params` or `prompt` parameter passed through.

**Answer: NO, the MCP OAuth flow does NOT support `prompt=select_account` or any custom authorize params.** The SSO flow supports it via env vars; the MCP tool server flow does not.

### Bottom line — viable approaches

| Approach | Viable? | Notes |
|----------|---------|-------|
| **(a) Pre-encrypted blob in `TOOL_SERVER_CONNECTIONS` env** | **YES** | Encrypt `OAuthClientInformationFull` with same `WEBUI_SECRET_KEY` via Fernet. Works because env var and DB are separate rails; env connections activate independently. Tedious to generate but mechanically sound. |
| **(b) Cleartext client creds in env JSON** | **YES (better)** | For `auth_type: oauth_2.1_static`, supply `oauth_client_id` and `oauth_client_secret` as cleartext in `info`. The `resolve_oauth_client_info()` overlays them onto the decrypted blob. You still need a valid (possibly minimal) `oauth_client_info` encrypted blob, but the actual creds can be cleartext. Even simpler: the `oauth_client_info` blob could be a minimal shell with just `redirect_uris`, `grant_types`, etc., and the real `client_id`/`client_secret` come from `info` fields. |
| **(c) Boot-time seed script via Admin API** | **YES (most practical)** | Run a script at boot that calls `POST /api/v1/configs/oauth/clients/register` with static creds (returns encrypted blob), then `POST /api/v1/configs/tool_servers` with the full connection config. But: with `ENABLE_PERSISTENT_CONFIG=False`, DB writes to `tool_server.connections` are ignored on next boot, so you'd need to re-seed every boot OR use `TOOL_SERVER_CONNECTIONS` env var instead. |
| **(d) Sidecar proxy** | **NOT NEEDED** | The env var path (a/b) works without a proxy. |

**Recommended:** Approach (b) — cleartext `oauth_client_id`/`oauth_client_secret` in `info` with `auth_type: oauth_2.1_static`, combined with a minimal pre-encrypted `oauth_client_info` blob (containing at minimum `redirect_uris`, `grant_types`, `response_types`, `client_name`). The env var `TOOL_SERVER_CONNECTIONS` is independent of `ENABLE_PERSISTENT_CONFIG`, so connections survive restarts declaratively.

**Remaining blocker:** No `prompt=select_account` support in MCP OAuth flow. For multi-account, users must authorize from an incognito/different browser session, or use separate OAuth clients.
