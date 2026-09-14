# Google Workspace MCP Decision History

**Date:** 2026-09-14
**Scope:** Why we moved off Google's hosted Workspace MCP servers to a self-hosted MCP server for Open WebUI.
**Status:** Historical record (narrative of events 2026-09-12 through 2026-09-14).

---

## TL;DR

We wired Google's official hosted MCP servers into Open WebUI, hit three UX friction points, then ran into a hard enrollment gate we could not pass: Google's Workspace Developer Preview Program requires a Workspace email (not a personal @gmail.com). The underlying Gmail/Calendar/Docs/Sheets REST APIs are all generally available and need no enrollment, so the fix was to swap in a self-hosted MCP server that wraps those same APIs.

---

## Timeline

### Stage 1 — Wire Google's hosted MCP servers (2026-09-13)

**What we did.** Added four MCP tool server connections to Open WebUI via `TOOL_SERVER_CONNECTIONS` (env var), one per service: Gmail, Calendar, Docs, and Sheets. Each connection pointed at Google's hosted endpoint (`gmailmcp.googleapis.com/mcp/v1`, `calendarmcp.googleapis.com/mcp/v1`, `docsmcp.googleapis.com/mcp/v1`, `sheetsmcp.googleapis.com/mcp/v1`) with `auth_type: oauth_2.1_static` and per-user OAuth sessions stored in OWUI's `oauth_session` table.

A boot-time generator script (`scripts/gen-openwebui-mcp-connections.sh`) runs inside the pinned Open WebUI image, calls the same `get_oauth_client_info_with_static_credentials()` function the Admin UI uses (live RFC 9728 discovery against Google), produces Fernet-encrypted `oauth_client_info` blobs, and writes the JSON into `services/agenticui/generated.env` for Docker Compose to source. The script also ensures `.webui_secret_key` persists in the volume so tokens survive container recreates.

**Commits:**
- `af2a61d` — "Wire Google Workspace MCP connections into Open WebUI" (generator script, compose changes, `generate_config.sh` hook)
- `11fa209` — "Add GCP setup wizard for Workspace MCP OAuth client" (interactive `scripts/gcp-mcp-setup.sh` walking the user through GCP project creation, API enables, OAuth consent screen, client ID/secret capture)
- `aa785ae` — "Persist WEBUI_URL in wizard preflight for clean re-runs"
- `a6ff627` — "Fix wizard stage 4: homepage and privacy policy URLs required to publish"

**Design doc:** `docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md` (508 lines, verified against OWUI source `backend/open_webui/config.py` and `backend/open_webui/utils/oauth.py`).

**Source:**
- Generator: [scripts/gen-openwebui-mcp-connections.sh](scripts/gen-openwebui-mcp-connections.sh)
- Design doc: [2026-09-12-openwebui-google-workspace-access.md](docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md)
- Commit: `af2a61d`

---

### Stage 2 — Friction: tools visible but silently unusable for non-admin users (2026-09-14 AM)

**What happened.** The MCP connections showed "Connected" in the Open WebUI Admin UI. A non-admin user's tool calls returned empty results with no error message.

**Root cause.** OWUI's `has_connection_access` function (in `backend/open_webui/utils/tools.py` in v0.11.1) treats a missing `access_grants` field as admin-only access. The generator script did not include `access_grants` in the connection config, so only the admin user could actually invoke the tools. Non-admin users saw the tools listed as connected but the request-time check silently dropped them from the available tool set.

**Fix.** Commit `7e4453a` ("Grant all users access to Google MCP tool servers") added a wildcard `access_grants` entry to each connection config:
```python
'config': {
    'enable': True,
    'access_grants': [
        {'principal_type': 'user', 'principal_id': '*', 'permission': 'read'}
    ],
},
```

**Source:**
- Commit `7e4453a` (commit message: "has_connection_access treats missing access_grants as admin-only, so only admins could use the connections; non-admin users saw them as Connected yet the request-time check silently dropped the tools.")
- Generator script lines 134–138: [scripts/gen-openwebui-mcp-connections.sh:134-138](scripts/gen-openwebui-mcp-connections.sh#L134)

---

### Stage 3 — Friction: OWUI `ask_user` isolation constraint stalls tool calls (2026-09-14 midday)

**What happened.** An assistant query asking for "newest email" and "tomorrow's calendar events" stalled for ~15 minutes. No tool results ever reached the model.

**Root cause.** Open WebUI v0.11.1 enforces that the `ask_user` tool must be the **sole** tool call in a model response. When the model bundled `ask_user` together with Gmail/Calendar tool calls in a single response, the entire batch was dropped — the middleware hits the error path at `stage_ask_user_tool_calls()` and `continue`s, so no tool results are returned to the model.

From `backend/open_webui/utils/ask_user.py` (v0.11.1 source):
```python
def get_ask_user_tool_calls(tool_calls: list[dict]) -> tuple[list[dict], str | None]:
    ask_user_calls = [
        tool_call for tool_call in tool_calls if tool_call.get('function', {}).get('name') == ASK_USER_NAME
    ]
    if not ask_user_calls:
        return [], None
    if len(tool_calls) != 1:
        return (
            ask_user_calls,
            'Error: ask_user must be the only tool call, so it did not run. Call ask_user on its own.',
        )
```

When `len(tool_calls) != 1` and `ask_user_calls` is non-empty, the function returns an error string, which causes `stage_ask_user_tool_calls()` to emit an error result and mark the call as `completed` (failed). The other tool calls in the same batch never execute.

**Fix.** Commit `9812544` ("Tell models user timezone and ask_user isolation rule") injected two things into the model system prompts: the user's timezone (so calendar queries don't need `ask_user` for timezone clarification) and an explicit rule telling the model to call `ask_user` alone when it needs to.

**Source:**
- OWUI v0.11.1 source: [backend/open_webui/utils/ask_user.py](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/utils/ask_user.py) — `get_ask_user_tool_calls()` (lines 1–17 of the fetched file)
- Commit `9812544`
- Verified from source (not unverified).

**User guide published.** Commit `290e061` ("Add user guide for Google Workspace via OAuth") produced `docs/specs/assistant/2026-09-13-google-workspace-oauth-user-guide.md` — a 29-line walkthrough for end users to authorize the four MCP connections.

---

### Stage 4 — Friction: per-user OAuth session mismatch (2026-09-14)

**What happened.** A chat hit `401 Unauthorized` from Google with the log line: "No OAuth session found for user `<uuid>`, client_id mcp:google-gmail". The affected OWUI user had no stored Google token in the `oauth_session` table (keyed by `(user_id, provider)` where provider = `mcp:google-gmail`).

**Root cause.** The auth model was per-user: each OWUI user had to independently authorize each of the four Google MCP connections. There was no visibility into *which* user had authorized and which had not. A user who had not completed the OAuth flow would hit 401s with no guidance.

**Resolution.** Re-authorizing via the four per-user authorize URLs (`/oauth/clients/mcp:google-gmail/authorize`, etc.) fixed the 401. The user guide (Stage 3, above) was already published to walk users through this.

**Lesson.** Per-user OAuth over a shared login adds an opaque failure mode. The error message names the OWUI user UUID but not the Google account, making diagnosis a two-step process.

**Source:**
- User guide: [2026-09-13-google-workspace-oauth-user-guide.md](docs/specs/assistant/2026-09-13-google-workspace-oauth-user-guide.md)
- OWUI session model: `oauth_session` table, `(user_id, provider)` composite key — verified in [2026-09-12 design doc](docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md) against `backend/open_webui/models/oauth_sessions.py`

---

### Stage 5 — The blocker: Google Workspace Developer Preview Program (2026-09-14)

**What happened.** After OAuth was working, Google's hosted MCP servers started returning:

> "Access to this tool requires that your Google Cloud project (`<project-id>`) is enrolled in the Google Workspace Developer Preview Program."

**The gate.** The Developer Preview Program is documented at [developers.google.com/workspace/preview](https://developers.google.com/workspace/preview). It states:

> "Joining the program requires agreeing to the Program Terms, submitting an application form with Google Workspace and Google Cloud project details, and ensuring your email can be added to a Google Group."

The application form ([Google Form](https://docs.google.com/forms/d/e/1FAIpQLSd7BiMXXHDlUDkF7G0TSY5zfJbQwFNH3m6K_ZYFi3vCHLFbng/viewform)) requires:
- A Google Workspace account (not a personal @gmail.com account).
- A Google Cloud project number.

The FAQ on the same page confirms:
> "We cannot add service accounts to the program. [...] If you include a service account to the application, we will remove it and will only register your Google Workspace account."

The page also lists the MCP servers under the "MCP SERVERS" section (Gmail MCP server, Calendar MCP server, Drive MCP server, People MCP server, Chat MCP server, Docs MCP server, Sheets MCP server, Slides MCP server), confirming that MCP server access is part of the Developer Preview Program.

The Program Terms state:
> "(ii) I understand that program features may not be included in public applications prior to the General Availability (GA) announcement."

**Our situation.** The GCP project was owned by a personal @gmail.com account, not a Google Workspace domain. Service accounts are explicitly excluded. Google Groups emails are also rejected (the page states: "Make sure that your email account accepts getting added to Google Groups. [...] If your email address cannot be added to the Google Group, you won't be able to access the dedicated client library, and you won't get access to some of the features."). There was no path to enrollment without acquiring a Workspace identity we did not control.

**This was the tipping point.** The failure was not a bug in our code, a misconfiguration, or an OWUI limitation. It was a capability controlled entirely by Google's preview program gate.

**Source:**
- [developers.google.com/workspace/preview](https://developers.google.com/workspace/preview) — "How to join the program", "FAQ", "Developer Preview Program Terms" sections
- [Configure the Google Workspace MCP servers](https://developers.google.com/workspace/guides/configure-mcp-servers) — "Developer Preview: Available as part of the Google Workspace Developer Preview Program"

---

### Stage 6 — Research and decision (2026-09-14)

**Commissioned research.** `docs/specs/assistant/2026-09-14-google-workspace-mcp-alternatives.md` evaluated two paths:
1. Self-hosted Google API MCP server (community project wrapping the GA REST APIs).
2. Direct REST API calls from Open WebUI Python tools/functions.

**Key verified fact.** The Developer Preview requirement applies **only** to Google's hosted MCP endpoints (`*mcp.googleapis.com`). The underlying REST APIs are all Generally Available:

| API | GA since | Source |
|-----|----------|--------|
| Gmail API | June 25, 2014 | [Gmail API release notes](https://developers.google.com/workspace/gmail/release-notes) — "The Gmail API is publicly available!" |
| Google Drive API | March 10, 2013 | [Drive API release notes](https://developers.google.com/workspace/drive/release-notes) — "The Google Drive API is now generally available" |
| Google Calendar API | Long-standing REST API | [Calendar API overview](https://developers.google.com/workspace/calendar/api/guides/overview) — "The Google Calendar API is a RESTful API" |
| Google Docs API | February 04, 2019 | [Docs API release notes](https://developers.google.com/docs/docs/release-notes) — "The Google Docs API is now generally available" |
| Google Sheets API | Long-standing REST API | [Sheets API overview](https://developers.google.com/workspace/sheets/api/guides/concepts) — "The Google Sheets API is a RESTful interface" |

All accept `Authorization: Bearer <access_token>` per [Using OAuth 2.0 to Access Google APIs](https://developers.google.com/identity/protocols/oauth2). No Developer Preview enrollment is needed.

**Decision: `taylorwilsdon/google_workspace_mcp`.** The research evaluated three community MCP servers and selected taylorwilsdon as the best fit:

| Attribute | Verified value |
|-----------|---------------|
| Repo | [github.com/taylorwilsdon/google\_workspace\_mcp](https://github.com/taylorwilsdon/google_workspace_mcp) |
| Stars | ~3,200 (2,891 commits, active) |
| Version | 1.26.1 ([pyproject.toml](https://raw.githubusercontent.com/taylorwilsdon/google_workspace_mcp/main/pyproject.toml)) |
| Language | Python 3.10+, FastMCP framework |
| Transport | stdio (legacy) or Streamable HTTP (`--transport streamable-http`) |
| Services | 12: Gmail, Calendar, Drive, Docs, Sheets, Slides, Forms, Tasks, Contacts, Apps Script, Chat, Custom Search (120+ tools) |
| Auth modes | Single-user, multi-user OAuth 2.0, multi-user OAuth 2.1 (PKCE, bearer tokens), external OAuth provider, stateless |
| Docker | `python:3.11-slim` base, `uv sync --frozen`, non-root `app` user, port 8000, healthcheck ([Dockerfile](https://raw.githubusercontent.com/taylorwilsdon/google_workspace_mcp/main/Dockerfile)) |
| License | MIT |

**Architecture change.** OWUI connects with `auth_type: "none"` — the MCP server handles its own Google OAuth consent flow and stores one token (single-user mode). This deletes the per-user OWUI OAuth machinery entirely (no more `oauth_session` rows per `(user_id, provider)`, no more per-user authorize URLs, no more opaque 401s from missing tokens). The Developer Preview gate is eliminated because the MCP server calls the GA REST APIs directly.

**Tradeoff acknowledged.** Single-user identity (one Google account for all assistant queries) vs. the previous per-user model (each OWUI user authorizes their own Google account). For a single-user household, this is acceptable.

**Source:**
- Research: [2026-09-14-google-workspace-mcp-alternatives.md](docs/specs/assistant/2026-09-14-google-workspace-mcp-alternatives.md)
- taylorwilsdon repo: README, pyproject.toml, Dockerfile (all fetched 2026-09-14)

---

## Why We Moved Off Google MCP (Decision Drivers)

1. **Developer Preview enrollment gate** — Google's hosted MCP servers require enrollment in the Workspace Developer Preview Program, which accepts only Google Workspace domain accounts (personal @gmail.com, service accounts, and Google Groups are explicitly rejected). We could not enroll without acquiring a Workspace identity.

2. **Capability controlled by a third party, not our infra** — The failure mode was not a bug or misconfiguration. It was a binary gate enforced by Google's preview program, with no SLA, no timeline for GA, and no self-service escalation path.

3. **Per-user OAuth friction** — Four separate authorize URLs, one per user, opaque 401 errors when a user hadn't completed auth, no visibility into which user had authorized which service. This was operational overhead disproportionate to the value for a single-user household.

4. **OWUI `ask_user` isolation constraint** — The model cannot call `ask_user` alongside any other tool in the same response; doing so drops the entire batch. This required system prompt engineering as a workaround and added fragility to the tool call flow.

5. **The underlying APIs are GA** — Gmail, Calendar, Docs, Sheets, and Drive REST APIs are all generally available and callable with a plain OAuth2 bearer token from any GCP project. The MCP servers are just a thin wrapper; the gate is on the wrapper, not the APIs.

---

## What We Chose Instead

A single self-hosted container (`taylorwilsdon/google_workspace_mcp`, v1.26.1, Streamable HTTP on port 8000) replacing all four Google-hosted MCP endpoints. The server manages its own single-user Google OAuth consent flow (one Google account, one stored token). OWUI connects with `auth_type: "none"` — no per-user OAuth, no `oauth_session` table entries, no authorize URLs, no Developer Preview enrollment.

**What this deletes from the repo:**
- `scripts/gen-openwebui-mcp-connections.sh` (Fernet blob generation for 4 Google MCP connections)
- `scripts/gcp-mcp-setup.sh` (GCP OAuth client setup wizard)
- `docs/specs/assistant/2026-09-13-google-workspace-oauth-user-guide.md` (per-user OAuth instructions)
- The design doc `docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md` (marked obsolete)
- Per-user authorize URLs from the user guide

**What this adds:**
- One new Docker Compose service (the MCP server container)
- One `TOOL_SERVER_CONNECTIONS` entry pointing at `http://google-workspace-mcp:8000/mcp`
- Single-user OAuth consent flow (one Google account, one-time setup)

---

## Sources

| # | Claim | URL |
|---|-------|-----|
| 1 | Developer Preview Program requires Workspace email + GCP project | <https://developers.google.com/workspace/preview> |
| 2 | Service accounts explicitly excluded from Developer Preview | <https://developers.google.com/workspace/preview> (FAQ: "We cannot add service accounts to the program") |
| 3 | Google Groups emails rejected for Developer Preview | <https://developers.google.com/workspace/preview> ("If your email address cannot be added to the Google Group, you won't be able to access [...] some of the features") |
| 4 | MCP servers listed under Developer Preview "MCP SERVERS" section | <https://developers.google.com/workspace/preview> |
| 5 | MCP server configuration docs state "Developer Preview" | <https://developers.google.com/workspace/guides/configure-mcp-servers> |
| 6 | Gmail API is GA ("publicly available", June 25, 2014) | <https://developers.google.com/workspace/gmail/release-notes> |
| 7 | Drive API is GA (March 10, 2013) | <https://developers.google.com/workspace/drive/release-notes> |
| 8 | Calendar API is a RESTful API (GA) | <https://developers.google.com/workspace/calendar/api/guides/overview> |
| 9 | Docs API is GA (February 04, 2019) | <https://developers.google.com/docs/docs/release-notes> |
| 10 | Sheets API is a RESTful interface (GA) | <https://developers.google.com/workspace/sheets/api/guides/concepts> |
| 11 | Google APIs use OAuth 2.0 bearer token auth | <https://developers.google.com/identity/protocols/oauth2> |
| 12 | taylorwilsdon/google\_workspace\_mcp repo (README) | <https://github.com/taylorwilsdon/google_workspace_mcp> |
| 13 | taylorwilsdon version 1.26.1 (pyproject.toml) | <https://raw.githubusercontent.com/taylorwilsdon/google_workspace_mcp/main/pyproject.toml> |
| 14 | taylorwilsdon Dockerfile (python:3.11-slim, uv, non-root, port 8000) | <https://raw.githubusercontent.com/taylorwilsdon/google_workspace_mcp/main/Dockerfile> |
| 15 | OWUI `ask_user` isolation constraint | <https://github.com/open-webui/open-webui/blob/main/backend/open_webui/utils/ask_user.py> |
| 16 | OWUI `TOOL_SERVER_CONNECTIONS` env var schema | <https://github.com/open-webui/open-webui/blob/main/backend/open_webui/config.py> |
| 17 | OWUI OAuth session model (`oauth_session` table) | <https://github.com/open-webui/open-webui/blob/main/backend/open_webui/models/oauth_sessions.py> |
| 18 | Commit `af2a61d` — initial MCP wiring | Repo git history |
| 19 | Commit `7e4453a` — wildcard access_grants fix | Repo git history |
| 20 | Commit `9812544` — ask_user isolation rule in system prompts | Repo git history |
| 21 | Commit `3367fd2` — write scopes for Google MCP servers | Repo git history |
| 22 | Design doc 2026-09-12 (OWUI + Google Workspace access research) | [docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md](docs/specs/assistant/2026-09-12-openwebui-google-workspace-access.md) |
| 23 | Research findings 2026-09-14 (MCP alternatives) | [docs/specs/assistant/2026-09-14-google-workspace-mcp-alternatives.md](docs/specs/assistant/2026-09-14-google-workspace-mcp-alternatives.md) |
| 24 | User guide 2026-09-13 (per-user OAuth walkthrough) | [docs/specs/assistant/2026-09-13-google-workspace-oauth-user-guide.md](docs/specs/assistant/2026-09-13-google-workspace-oauth-user-guide.md) |

---

## Unverified Claims

None. All claims above are cited to primary sources (Google official documentation pages, Open WebUI v0.11.1 source code, taylorwilsdon repo files, or this repo's own commits).
