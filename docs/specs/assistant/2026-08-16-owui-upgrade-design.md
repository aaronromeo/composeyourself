# D1 — OpenWebUI Upgrade Design (v0.9.6 → v0.11.0)

_Date: 2026-08-16. Status: approved design, pre-plan._

Deliverable 1 of the Assistant work: upgrade OpenWebUI and switch on — as code —
the capabilities that were missing in the precipitating incident (web search that
actually executes, Sub-agents, Automations). Deliverable 2 (n8n deployment +
integration) is out of scope here and gets its own design cycle.

Read first: [`CONTEXT.md`](./CONTEXT.md) (glossary),
[`2026-08-16-assistant-research-brief.md`](./2026-08-16-assistant-research-brief.md)
(R1–R13), [`2026-08-16-assistant-research-findings.md`](./2026-08-16-assistant-research-findings.md),
[`../../adr/0001-self-hosted-assistant-only.md`](../../adr/0001-self-hosted-assistant-only.md).

## Decisions locked

- **Search engine:** self-hosted **SearXNG**, new container on sweetpaintedlady,
  internal to the `cys-service` network (no public port, no Caddy/Authelia
  exposure).
- **Sub-agent cost guardrails:** conservative — max 5 concurrent foreground, 3
  background, 10 tool-call iterations per sub-agent.
- **Config authority:** `ENABLE_PERSISTENT_CONFIG=False` permanently
  ("Approach A"). Env vars are authoritative on every boot; Admin UI changes are
  session-only and revert on restart. Upstream documents exactly this use case.

## Why this fixes the incident

On v0.9.6 the chat was in Legacy mode: a per-chat "Web Search" toggle RAG-injects
results only if an engine is configured — none was, so the model truthfully
reported it had no search. In v0.11 (Native mode, default since v0.10.0) the
model itself calls `search_web`/`fetch_url` as **visible tool calls** —
platform-executed, verifiable, never model-asserted (R1 satisfied structurally).
Repeated search/fetch loops with interleaved thinking provide Deep Research (R2);
`delegate_task` provides Orchestration (R3); RRULE-scheduled Automations provide
the Trigger half of Background Goals (R4 capability, no goals registered in D1).

## Section 1 — Architecture & configuration

Components (sweetpaintedlady overlay only; caddy/authelia/otelcol untouched):

1. **`openwebui`** — image pin `ghcr.io/open-webui/open-webui:v0.9.6` →
   `ghcr.io/open-webui/open-webui:v0.11.0`. No other structural change.
2. **`searxng`** — new service on `cys-service`. No host port. Committed config
   under `services/searxng/`: `settings.yml` (with `json` added to
   `search.formats` — without it SearXNG 403s OWUI's queries) and
   `limiter.toml` (non-restrictive; the instance is network-internal anyway).
   Healthcheck, `restart: unless-stopped`, memory limit ~256M, `cap_drop: ALL`
   after first-run init (see Deploy wrinkle, Section 2).

New env on the `openwebui` service:

```yaml
# Config authority: env wins, always. UI changes are session-only.
- ENABLE_PERSISTENT_CONFIG=False
# Web search (SearXNG)
- ENABLE_WEB_SEARCH=True
- WEB_SEARCH_ENGINE=searxng
- SEARXNG_QUERY_URL=http://searxng:8080/search?q=<query>
- WEB_SEARCH_RESULT_COUNT=5
- WEB_SEARCH_CONCURRENT_REQUESTS=10
# Capabilities that didn't exist on v0.9.6
- ENABLE_AUTOMATIONS=True
- ENABLE_SUBAGENTS=True
- SUBAGENTS_BACKGROUND_ENABLED=True
# Cost guardrails
- SUBAGENTS_MAX_CONCURRENT=5
- SUBAGENTS_MAX_ASYNC=3
- SUBAGENTS_MAX_ITERATIONS=10
# Native function calling as global default (belt-and-braces; default since v0.10)
- DEFAULT_MODEL_PARAMS={"function_calling":"native"}
# Default model (see simplification below)
- DEFAULT_MODELS=anthropic/claude-sonnet-4.6
```

**Simplification from Approach A:** with env authoritative on every boot,
`DEFAULT_MODELS` just works — the `config.json` re-copy step in
`generate_config.sh` (which exists only because of the PersistentConfig gotcha)
can be retired. `seed-openwebui.sh` stays: model presets are data rows seeded
via the import API, unaffected by `ENABLE_PERSISTENT_CONFIG`.

**Resolved (plan phase):** `DEFAULT_MODEL_METADATA` env var gives ALL models
`web_search` + `builtin_tools` capabilities at startup — including raw
OpenRouter models that have no `models.json` entry. It is explicitly applied
even with persistent config disabled. No `models.json` capabilities edit is
needed. The `defaultFeatureIds: ["web_search"]` key in the same env var makes
web search on-by-default in new chats for all models.

**Doc updates in scope:** `AGENTS.md` and `SERVICES.md` must state that
`ENABLE_PERSISTENT_CONFIG=False` means Admin UI edits do not persist across
restarts, and that config changes go through the repo + `update.sh`.

## Section 2 — Upgrade procedure & rollback

Pre-upgrade (on sweetpaintedlady, as `dockerops`):

1. **Backup the DB.** `webui.db` holds a year of chat history and DB migrations
   are forward-only — take a timestamped copy of `services/agenticui/` before
   touching anything. This is the rollback anchor.
2. **Land the repo changes** (workspace → git → pull on host): image pin,
   `searxng` service + `services/searxng/` config, the env block, the
   `generate_config.sh` simplification, the doc updates.

Deploy:

3. `./update.sh sweetpaintedlady` — existing machinery: pulls the repo,
   validates `docker compose config` pre-flight, pulls images, hands down/up to
   `restart.sh`, re-seeds presets. No new machinery in D1.
4. **SearXNG first-run wrinkle.** Upstream notes the container needs write
   capabilities on first boot to generate `uwsgi.ini` (either one boot without
   `cap_drop`, or a small permanent `cap_add` list — the two upstream recipes
   differ). The plan pins the exact sequence against the pinned image. All
   other SearXNG config is committed files, no generation.

Post-deploy: verify `/api/version` reports v0.11.0, then run Section 3's
acceptance tests.

Rollback:

- Pin the image back to `v0.9.6`, restore the `webui.db` backup,
  `./restart.sh sweetpaintedlady`.
- SearXNG is purely additive — worst case it sits unused.
- Config-only problems need no DB surgery: fix the env var in the repo,
  re-run `update.sh` — env wins every boot.

## Section 3 — Failure modes & acceptance tests

Failure modes (everything degrades honestly, nothing silently):

1. **SearXNG down/unhealthy** → `search_web` returns an error to the model →
   the model reports search unavailable; chat otherwise works. Healthcheck +
   restart policy; the edge collector already tails its logs into SigNoz.
2. **SearXNG 403s** → the missing-`json`-format problem; prevented by the
   committed `settings.yml`.
3. **A model lacks the Web Search capability/default feature** → tools never
   get injected → the model says it can't search. Same honest failure as the
   original incident, but the cause is now a visible line in `models.json`, not
   invisible DB state.
4. **Cost runaway from orchestration** → capped structurally by the 5/3/10
   limits; spend observed in the OpenRouter dashboard (out of repo scope).
5. **"My UI edit didn't stick"** → intended behavior under
   `ENABLE_PERSISTENT_CONFIG=False`; documented in `AGENTS.md`/`SERVICES.md`,
   proven by T5.
6. **Known limitation, not fixed in D1:** Automations are process-bound — a
   container restart kills a running automation. Acceptable in D1 because no
   standing goals are registered here; the Junior Blues goal lands with n8n's
   durable queue in D2.

Acceptance tests (run after deploy):

| # | Test | Pass condition |
|---|---|---|
| T1 | Search-and-Summarize: "what are today's top Hacker News stories?" | Visible `search_web` tool call; answer cites links |
| T2 | Deep Research: "research the current state of mesh wifi standards" | Multiple visible search/fetch loops; cited report |
| T3 | Orchestration: "research X, Y, Z in parallel with sub-agents" | `delegate_task` calls visible; never more than 5 concurrent |
| T4 | Automations: "schedule a daily summary at 9am" | `create_automation` tool creates it; Run Now produces a chat |
| T5 | Determinism: flip a setting in Admin UI, then `./restart.sh sweetpaintedlady` | Setting reverts to the repo value |
| T6 | Pre-flight | `docker compose config` validates (update.sh enforces) |

Rollback drill (Section 2) is documented; executing it is optional.

## Non-goals for D1

- No n8n, no Zettelkasten write-path, no Notifications — Deliverable 2.
- No standing Background Goals registered (Junior Blues arrives in D2).
- Mailbox (Fastmail) and Calendar integrations untouched.
- No multi-user changes; single user behind the existing Authelia OIDC.

## Sources

- OpenWebUI releases (v0.11.0, published 2026-07-27): <https://github.com/open-webui/open-webui/releases>
- Agentic search & Native mode (tools, three switches, interleaved thinking): <https://docs.openwebui.com/features/chat-conversations/web-search/agentic-search/>
- SearXNG provider setup (JSON format requirement, query URL shape, caps): <https://docs.openwebui.com/features/chat-conversations/web-search/providers/searxng/>
- Env configuration (`ENABLE_PERSISTENT_CONFIG` semantics, ConfigVar behavior, web search vars): <https://docs.openwebui.com/reference/env-configuration>
- Sub-agents (enablement, limits, background mode): <https://docs.openwebui.com/features/chat-conversations/chat-features/subagents/>
- Automations (RRULE, builtin tools, process-bound worker): <https://docs.openwebui.com/features/chat-conversations/chat-features/automations/>
