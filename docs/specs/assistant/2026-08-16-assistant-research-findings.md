# Assistant Research Findings

_Date: 2026-08-16. Verification date: 2026-08-16._

## 1. Candidate Longlist

### 1.1 OpenWebUI (Keep + Extend) — v0.11.0

OpenWebUI is the current Assistant, now at v0.11.0 (user is on v0.9.6). The gap between 0.9.6 and 0.11.0 is substantial: v0.10.0 introduced Native (Agentic) Mode as default, Interleaved Thinking for Deep Research, native Sub-agents with foreground/background delegation, and Automations (scheduled prompts with RRULE). v0.11.0 added chat timers, folder collaboration, and notification targets with "always" delivery mode. Web search is a builtin tool (`search_web` + `fetch_url`) configurable via environment variables (`ENABLE_WEB_SEARCH`, `WEB_SEARCH_ENGINE`, `SEARXNG_QUERY_URL`) and the Admin UI. Skills are first-class (markdown instruction sets, `$` mention, model binding with lazy loading). MCP support is native (Streamable HTTP). Notifications support user-configurable webhook targets (Discord-compatible) with a `notify` builtin tool. Export exists as JSON (Settings > Data Controls) and raw `webui.db` copy. The mobile web UI is the primary interface. The main gap: no native git-commit tool for Zettelkasten writes (requires a custom Tool or MCP server), and PersistentConfig means some settings seed from env vars but are then overridden by the database — a known gotcha.

**Sources:**
- Features overview: <https://docs.openwebui.com/features/>
- Web Search / Agentic Search: <https://docs.openwebui.com/features/chat-conversations/web-search/agentic-search/>
- SearXNG setup: <https://docs.openwebui.com/features/chat-conversations/web-search/providers/searxng/>
- Sub-agents: <https://docs.openwebui.com/features/chat-conversations/chat-features/subagents/>
- Automations: <https://docs.openwebui.com/features/chat-conversations/chat-features/automations/>
- Skills: <https://docs.openwebui.com/features/workspace/skills/>
- Notifications / User Webhooks: <https://docs.openwebui.com/features/chat-conversations/chat-features/notifications/>
- MCP support: <https://docs.openwebui.com/features/extensibility/mcp/>
- Tools (builtin list): <https://docs.openwebui.com/features/extensibility/plugin/tools/>
- Import/Export: <https://docs.openwebui.com/features/chat-conversations/data-controls/import-export/>
- Database schema / backups: <https://docs.openwebui.com/reference/database-schema/>
- v0.11.0 release blog: <https://www.openwebui.com/blog/v0-11-0-the-interface-reorganized/>
- Releases: <https://github.com/open-webui/open-webui/releases>
- Env var reference: <https://docs.openwebui.com/reference/env-configuration/>

### 1.2 Dify — v1.16.x

Dify is an open-source LLM app development platform with a visual workflow builder, Agent nodes (function-calling and ReAct strategies), and a new Dify Agent runtime (Linux sandbox, SKILL.md support). It supports Schedule Triggers (cron expressions) for background workflow execution, Webhook Triggers, and Integration Triggers. Web search is available as a built-in tool. The Agent node can be used inside workflows for Orchestration. Dify accepts OpenAI-compatible endpoints including OpenRouter. Self-hosted via Docker Compose (15+ containers: api, api_websocket, worker, worker_beat, web, plugin_daemon, agent_backend, weaviate, postgres, redis, nginx, ssrf_proxy, agent_ssrf_proxy, sandbox, local_sandbox). The web app is responsive but not specifically optimized as a mobile-first chat interface. Chat export is not a first-class feature (logs exist but no user-facing "export my chats" button). Resource footprint is heavy for a CPX21.

**Sources:**
- Homepage: <https://dify.ai/>
- Docker Compose deploy: <https://docs.dify.ai/en/self-host/quick-start/docker-compose>
- Agent node docs: <https://docs.dify.ai/en/self-host/use-dify/nodes/agent>
- Dify Agent overview: <https://docs.dify.ai/en/self-host/use-dify/build/new-agent/overview>
- Build an Agent (SKILL.md): <https://docs.dify.ai/en/self-host/use-dify/build/new-agent/build>
- Schedule Trigger: <https://docs.dify.ai/en/self-host/use-dify/nodes/trigger/schedule-trigger>
- Trigger overview: <https://docs.dify.ai/en/self-host/use-dify/nodes/start>
- Compose file (container count): <https://github.com/langgenius/dify/blob/HEAD/docker/docker-compose.yaml>
- GitHub: <https://github.com/langgenius/dify>
- System requirements (CPU >= 2 Core, RAM >= 4 GiB): <https://github.com/langgenius/dify> (README quick-start)

### 1.3 n8n (+ OpenWebUI as chat front-end) — v2.25.x

n8n is a fair-code workflow automation platform with 400+ integrations, LangChain-based AI Agent nodes, Schedule Triggers (cron), and native Discord nodes (send via webhook or bot). It excels at Background Goals: the Schedule Trigger fires workflows on cron, the AI Agent node performs web search (Brave, SearXNG, SerpAPI) and multi-step reasoning, and the Discord node delivers Notifications. n8n has no native chat UI — its "Chat Trigger" provides a basic test widget, not a mobile-friendly conversation interface. The community project n8n-claw demonstrates n8n as a full agent with Telegram/Discord chat, memory, web search (SearXNG), scheduled actions, and sub-agent delegation, but it uses Telegram/Discord as the chat interface, not a web UI. n8n is best positioned as a Background Goal sidecar to OpenWebUI, not a replacement for the chat interface.

**Sources:**
- Docker install: <https://docs.n8n.io/deploy/host-n8n/install-options/install-with-docker>
- Docker Compose hosting: <https://github.com/n8n-io/n8n-hosting>
- AI Agent node: <https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.agent/>
- Schedule Trigger: <https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.scheduletrigger/>
- Web search in agents (PR): <https://github.com/n8n-io/n8n/pull/30789>
- n8n-claw (community agent stack): <https://github.com/freddy-schuetz/n8n-claw>
- Self-hosted guide (queue mode, scaling): <https://joshuaopolko.com/n8n-self-hosted-guide/>
- Version 2.25.7 release: <https://joshuaopolko.com/n8n-self-hosted-guide/> (cites current release)

### 1.4 Flowise — v3.x

Flowise is a visual drag-and-drop LLM workflow builder built on LangChain.js. It supports Agentflows (multi-agent with tool use), web search tools (SerpAPI, Brave), and can deploy flows as REST APIs or MCP servers. Docker Compose deploy is straightforward (1–3 containers). However, it has no native scheduling for background execution (no cron trigger node), no native Skills concept, and its chat interface is an embeddable widget rather than a standalone mobile web app. The UI is a workflow builder, not a conversation-first interface.

**Sources:**
- GitHub: <https://github.com/FlowiseAI/Flowise>
- Docker Compose: <https://docs.flowiseai.com/getting-started>
- Queue mode / worker: <https://github.com/FlowiseAI/Flowise/blob/main/docker/README.md>
- Compose file: <https://github.com/FlowiseAI/Flowise/blob/main/docker/docker-compose.yml>
- Self-hosting guide: <https://selfhosting.sh/apps/flowise/>

### 1.5 Langflow — v1.11.x

Langflow is a Python-based visual AI workflow builder (LangChain) with multi-agent orchestration, MCP server deployment, and custom Python components. Docker Compose deploy with PostgreSQL is well-documented. However, it has no native scheduling/cron triggers, no Skills concept, no native chat UI (the "playground" is for testing flows, not a persistent conversation interface), and no mobile-first web UI. It is a workflow builder, not a conversation-first Assistant.

**Sources:**
- GitHub: <https://github.com/langflow-ai/langflow>
- Docker deploy: <https://docs.langflow.org/deployment-docker>
- Multi-worker: <https://docs.langflow.org/deployment-multi-worker>
- Deployment overview: <https://docs.langflow.org/deployment-overview>
- Self-hosting guide: <https://selfhosting.sh/apps/langflow/>

### 1.6 Other candidates considered and excluded

- **Hermes Agent + Hermes Studio** (NousResearch): Strong sub-agent delegation, cron scheduling, SKILL.md support, but the chat UI is Hermes Studio — a dashboard for power users, not a mobile-first chat interface. Requires Hermes Agent gateway. <https://github.com/JPeetz/Hermes-Studio>
- **SwarmClaw**: Multi-agent runtime with schedules, MCP, 24+ providers, but focused on OpenClaw operators and code-centric workflows. No standalone mobile chat UI. <https://github.com/swarmclawai/swarmclaw>
- **AG3NT**: Local-first multi-agent with scheduler (heartbeat + cron), SKILL.md, Discord adapter, but the web UI is a dashboard, not a mobile-first chat. Early-stage (milestones M1–M8 complete). <https://github.com/AP3X-Dev/AG3NT>
- **OwnPilot**: Privacy-first assistant with autonomous agents, 250+ tools, Telegram/WhatsApp, but the web UI is React-based and heavy; no clear Docker Compose deploy story for the CPX21. <https://github.com/ownpilot/OwnPilot>
- **HubOS**: Multi-user AI workforce platform, Chinese-first, overkill for single-user. <https://github.com/hubos-ai/HubOS>
- **TigrimOS**: macOS/Windows desktop app, not Docker-deployable. <https://github.com/Sompote/Tigrimos>

---

## 2. Shortlist Scoring Matrix (R1–R13)

Shortlist: **OpenWebUI (v0.11.0)**, **OpenWebUI + n8n sidecar**, **Dify (v1.16.x)**.

| Req | Description | OpenWebUI v0.11.0 | OpenWebUI + n8n | Dify v1.16.x |
|-----|-------------|-------------------|-----------------|--------------|
| **R1** | Search-and-Summarize: platform-executed, citations, configured as code | **PASS** — `search_web` + `fetch_url` builtin tools; env vars `ENABLE_WEB_SEARCH`, `WEB_SEARCH_ENGINE`, `SEARXNG_QUERY_URL` seed config; results include links. ConfigVar persistence is a known gotcha (env seeds, DB overrides). <br><https://docs.openwebui.com/features/chat-conversations/web-search/agentic-search/> <br><https://docs.openwebui.com/reference/env-configuration/> | **PASS** — Same as OWUI for chat; n8n can also do search via SearXNG/Brave tools. <br><https://github.com/n8n-io/n8n/pull/30789> | **PASS** — Built-in Google Search tool in Agent node; configurable in workspace. <br><https://docs.dify.ai/en/self-host/use-dify/nodes/agent> |
| **R2** | Deep Research: long-running multi-source cited report | **PASS** — Interleaved Thinking (Native Mode) enables model to search→fetch→evaluate→iterate→synthesize in a loop. `search_web` + `fetch_url` (50k char extraction) with agentic research loop. <br><https://docs.openwebui.com/features/chat-conversations/web-search/agentic-search/> | **PASS** — Same as OWUI for interactive; n8n can run multi-step research workflows on schedule. <br><https://lodd.dev/blog/n8n-marketing-agent> | **PASS** — Multi-agent workflows with Research Planner → Source Finder → Summarizer → Reviewer → Writer pattern. <br><https://www.langflow.org/blog/how-to-build-a-deep-research-multi-agent-system> (Langflow blog, but Dify supports same pattern via Agent nodes) <br><https://docs.dify.ai/en/self-host/use-dify/nodes/agent> |
| **R3** | Orchestration: lead agent decomposes and delegates to sub-agents | **PASS** — `delegate_task` builtin tool with foreground (wait) and background (async) sub-agents. Max concurrent configurable. <br><https://docs.openwebui.com/features/chat-conversations/chat-features/subagents/> | **PASS** — Same OWUI sub-agents + n8n can orchestrate multi-agent workflows. <br><https://docs.openwebui.com/features/chat-conversations/chat-features/subagents/> | **PASS** — Agent node inside workflows; can invoke other agents as steps. Dify Agent has sandbox + tool loop. <br><https://docs.dify.ai/en/self-host/use-dify/nodes/agent> <br><https://docs.dify.ai/en/self-host/use-dify/build/new-agent/overview> |
| **R4** | Background Goals with Triggers: scheduled autonomous pursuit | **PASS** — Automations feature: RRULE schedules (hourly/daily/weekly/monthly/custom), background worker loop (`SCHEDULER_POLL_INTERVAL`), "Run Now", pause/resume, execution history. <br><https://docs.openwebui.com/features/chat-conversations/chat-features/automations/> | **PASS** — OWUI Automations + n8n Schedule Trigger (cron) for heavier workflows. <br><https://docs.openwebui.com/features/chat-conversations/chat-features/automations/> <br><https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.scheduletrigger/> | **PASS** — Schedule Trigger node (cron expressions, visual picker). Workflow runs automatically. <br><https://docs.dify.ai/en/self-host/use-dify/nodes/trigger/schedule-trigger> |
| **R5** | Notifications: proactive delivery via Discord webhook | **PASS** — User webhook notification targets (Settings > Notifications), `notify` builtin tool, `away`/`always` delivery modes. Discord-compatible webhook. <br><https://docs.openwebui.com/features/chat-conversations/chat-features/notifications/> | **PASS** — Same OWUI notifications + n8n Discord node (webhook or bot) for n8n-triggered alerts. <br><https://docs.openwebui.com/features/chat-conversations/chat-features/notifications/> <br><https://www.theagentecosystem.com/blog/n8n-discord-ai-agent> | **PARTIAL** — No native notification system. Must build HTTP Request node to Discord webhook in workflow. Works but not integrated. <br><https://docs.dify.ai/en/self-host/use-dify/nodes/trigger/webhook-trigger> |
| **R6** | Zettelkasten write-path: commit to GitHub repo | **PARTIAL** — No native git tool. Requires a custom Workspace Tool (Python script using `gh` or PyGitHub) or an MCP server for git operations. Feasible but not out-of-the-box. <br><https://docs.openwebui.com/features/extensibility/plugin/tools/> | **PASS** — n8n has GitHub node (create file, commit) that can be triggered from OWUI automation or n8n workflow. <br><https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.github/> | **PARTIAL** — No native git tool. Must use HTTP Request node to GitHub API in a workflow. Feasible but not integrated. <br><https://docs.dify.ai/en/self-host/use-dify/workspace/tools> |
| **R7** | Dual-format output: human-readable + agent-ingestible markdown | **PASS** — All chat output is markdown; automations produce real chats with full message history exportable as JSON. <br><https://docs.openwebui.com/features/chat-conversations/data-controls/import-export/> | **PASS** — Same as OWUI. <br><https://docs.openwebui.com/features/chat-conversations/data-controls/import-export/> | **PASS** — Workflow outputs are structured; Agent node returns text + files. <br><https://docs.dify.ai/en/self-host/use-dify/nodes/agent> |
| **R8** | Skills: reusable prompt/workflow packages invocable by name | **PASS** — First-class Skills: markdown instruction sets, `$` mention, per-chat toggle, model binding with lazy loading (`view_skill` tool), import/export. <br><https://docs.openwebui.com/features/workspace/skills/> | **PASS** — Same OWUI Skills + n8n workflow templates serve as reusable automation patterns. <br><https://docs.openwebui.com/features/workspace/skills/> | **PASS** — Dify Agent supports SKILL.md (agentskills.io spec). Skills can be attached to agents. <br><https://docs.dify.ai/en/self-host/use-dify/build/new-agent/build> |
| **R9** | Model-backend agnostic: OpenAI-compatible, swappable | **PASS** — Supports OpenAI-compatible endpoints (OpenRouter, any OpenAI-compatible API), Ollama, Anthropic-compatible API (`/api/v1/messages`). Multiple model presets. <br><https://docs.openwebui.com/reference/> <br><https://docs.openwebui.com/features/extensibility/> | **PASS** — Same as OWUI for chat; n8n supports OpenAI, Anthropic, Ollama, any OpenAI-compatible. <br><https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.agent/> | **PASS** — Supports OpenAI, Anthropic, OpenRouter, Gemini, Ollama, and any OpenAI-compatible endpoint. <br><https://docs.dify.ai/en/self-host/use-dify/build/new-agent/build> |
| **R10** | Self-hosted deployment: Docker Compose, Authelia, config-as-code | **PASS** — Already deployed via composeyourself. Single container (plus optional SearXNG). Env var config + generated config.json. <br><https://docs.openwebui.com/reference/env-configuration/> | **PASS** — OWUI as now + n8n as additional compose service (PostgreSQL + Redis + worker for queue mode). Both behind Authelia. <br><https://github.com/n8n-io/n8n-hosting/tree/main/docker-compose/withPostgresAndWorker> | **PASS** — Docker Compose deploy documented. 15+ containers. All env-var configurable. <br><https://docs.dify.ai/en/self-host/quick-start/docker-compose> |
| **R11** | Mobile web UI | **PASS** — Mobile web UI is the primary interface; responsive Svelte frontend. <br><https://docs.openwebui.com/features/> | **PASS** — Same OWUI mobile UI. <br><https://docs.openwebui.com/features/> | **PARTIAL** — Web app exists but is workflow-builder-first, not mobile-optimized chat. <br><https://docs.dify.ai/en/self-host/use-dify/build/additional-features> |
| **R12** | Single user | **PASS** — Works for single user; multi-user is optional. <br><https://docs.openwebui.com/features/authentication-access/> | **PASS** — Same. | **PASS** — Single workspace, single user works. <br><https://docs.dify.ai/en/self-host/deploy/overview> |
| **R13** | Exit-ability: data exportable at any time | **PASS** — JSON chat export (Settings > Data Controls), raw `webui.db` copy, skills/tools export as JSON. <br><https://docs.openwebui.com/features/chat-conversations/data-controls/import-export/> <br><https://docs.openwebui.com/tutorials/maintenance/backups/> | **PASS** — Same OWUI export + n8n workflow JSON export. <br><https://docs.openwebui.com/features/chat-conversations/data-controls/import-export/> | **PARTIAL** — Workflow DSL export exists. Chat logs exist but no user-facing "export all my conversations" feature. <br><https://docs.dify.ai/en/self-host/use-dify/build/new-agent/build> |

---

## 3. Recommendation

### Recommended: OpenWebUI v0.11.0 + n8n sidecar

**Rationale:**

OpenWebUI v0.11.0 clears the switching bar on its own for R1–R5, R7–R9, R11–R13. The gap between the user's current v0.9.6 and v0.11.0 is the key insight: v0.10.0 added the features that were missing when the brief was written (Automations, Sub-agents, Native Mode, Interleaved Thinking, Notification targets). Upgrading alone resolves the precipitating incident (web search configured as code with SearXNG) and adds Background Goals, Orchestration, Skills, and Notifications — all natively.

The two gaps in standalone OpenWebUI are:
- **R6 (Zettelkasten write-path):** No native git-commit tool. This is solvable with a single Workspace Tool (Python script) or a lightweight MCP server.
- **Heavy Background Goals:** The canonical example (weekly page monitoring → calendar event → Discord message) involves browser automation and external API calls that would compete with OpenWebUI for the CPX21's 4 GB RAM.

Adding n8n as a sidecar solves both: n8n handles the heavy Background Goals (scheduled web monitoring, git commits to Zettelkasten, complex multi-step workflows) while OpenWebUI remains the chat interface. n8n runs in queue mode on the Worker Host (rocketman), keeping the Interface Host lean. n8n's GitHub node handles Zettelkasten commits natively, and its Discord node handles Notifications from scheduled workflows.

**Why not Dify:** Dify is a capable platform but its 15+ container footprint is too heavy for a CPX21 already running Caddy, Authelia, OpenWebUI, and otelcol. Its web UI is workflow-builder-first, not a mobile-first chat interface (R13 concern). Migrating a year of chat history from `webui.db` to Dify has no established path. Dify's strength (visual workflow building) overlaps with what n8n does better as a dedicated automation engine.

**Why not replace OpenWebUI entirely:** Flowise and Langflow lack native scheduling and mobile chat UIs. The specialized agent platforms (Hermes, SwarmClaw, AG3NT) lack mobile-first chat interfaces and mature Docker Compose deploy stories. None offers a better chat experience than OpenWebUI for a single user on mobile.

### Migration Cost

- **OpenWebUI upgrade (v0.9.6 → v0.11.0):** Low risk. The `webui.db` SQLite database is forward-compatible. The PersistentConfig gotcha means some settings may need re-seeding via env vars after upgrade (notably `ENABLE_WEB_SEARCH`, `WEB_SEARCH_ENGINE`, `SEARXNG_QUERY_URL`). The `generate_config.sh` script already handles config.json re-copying. Chat history, models, skills, and automations persist in the database.
- **n8n sidecar addition:** New service. Requires PostgreSQL + Redis + n8n main + n8n worker containers. Deploy on rocketman (Worker Host) to avoid CPX21 resource pressure. Workflows are imported as JSON (config-as-code).
- **Zettelkasten git tool:** One Workspace Tool (Python) or one MCP server to add. ~100 lines of Python using `gh` CLI or PyGitHub.

### How Exit-ability (R13) is Preserved

- OpenWebUI's JSON chat export and `webui.db` backup continue to work.
- n8n workflows are exportable as JSON (version-controlled in composeyourself).
- All configuration is in composeyourself as code (compose overlays, generated configs, seeded presets).
- No vendor lock-in: model backends remain swappable via OpenAI-compatible endpoints.
- Skills are exportable as JSON and stored as markdown (portable format).

---

## 4. Interaction Patterns — how OpenWebUI and n8n talk

**OpenWebUI and n8n DO interact.** There is one designed request leg and three
return legs:

```
(1) OpenWebUI ──tool call: POST webhook───> n8n          the request leg (designed)
(2) n8n ──HTTP to announcements webhook───> Discord      primary return path
(3) n8n ──GitHub node: commit file───────> Zettelkasten  artifact return path
(4) n8n ──REST API (Bearer sk-…)─────────> OpenWebUI     optional: result lands as a new saved chat
```

Leg (1) is how chat-initiated work starts; legs (2)–(4) are how results come
back. A purely scheduled Background Goal uses none of leg (1) — n8n fires on
its own.

### Pattern 1 — Synchronous: chat → n8n → chat (fast jobs, seconds)

- The model calls a **Workspace Tool** (small Python function, exported as JSON
  into composeyourself) which POSTs `{title, markdown}` to the n8n webhook's
  **production URL** over Tailscale.
- The webhook is configured **Respond: When Last Node Finishes**, so the
  workflow (e.g. the GitHub node commits `YYYYMMDDHHMMSS_title.md` to `main`)
  runs to completion and its output becomes the HTTP response — which becomes
  the **tool result** the model continues with ("Saved: <commit URL>").
- Only for jobs finishing in seconds: the chat blocks on the tool call.
  Anything longer belongs in Pattern 2.

### Pattern 2 — Ack now, answer later: chat → 200 immediately → Notification

- Same tool-call leg, but the webhook is configured **Respond: Immediately**:
  n8n returns `200 "Workflow got started"` at once and the chat is unblocked.
- The workflow (e.g. a Deep Research run: AI Agent node with a SearXNG tool)
  takes minutes; the result arrives decoupled, via leg (2) Discord and/or leg
  (3) a committed Zettelkasten note.

### Pattern 3 — Scheduled: no requester at all

- An n8n **Schedule Trigger** (cron) on the Worker Host fires the canonical
  Saturday registration check: fetch page → AI Agent semantic check → on a hit,
  commit an ICS file to the Zettelkasten and send a Discord Notification.
  OpenWebUI is involved in nothing here.

### Return leg (4) — n8n → OpenWebUI (optional, documented)

OpenWebUI exposes a full REST API with Bearer API keys that are scoped to a user
and can be restricted to specific endpoints. n8n can call
`POST /api/chat/completions` with chat saving enabled, so a finished Background
Goal appears as a **new chat** in the user's list. Appending into an existing
conversation is not a first-class pattern. If used: mint a separate
**non-admin** key for n8n — the existing `OPENWEBUI_API_KEY` is admin and
reserved for preset seeding.

### Gotchas that shape the deployment

- **Production webhook URLs only exist on published workflows.** The
  `/webhook-test/` URL is editor-only; tools must use `/webhook/…`.
- **Synchronous responses hold the HTTP connection for the whole run** — keep
  Pattern 1 to fast jobs.
- **n8n queue mode persists executions** (Postgres/Redis), so a Worker Host
  restart doesn't silently kill a running goal — unlike OpenWebUI Automations,
  which are process-bound.
- **Credentials live in n8n** (GitHub token, Model Backend keys), encrypted via
  `N8N_ENCRYPTION_KEY`. OpenWebUI knows only the webhook URL and one header
  secret — a compromised chat prompt can't exfiltrate GitHub credentials.

**Sources:**
- Webhook node (respond modes, auth, test vs production): <https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/>
- Schedule Trigger: <https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.scheduletrigger/>
- OpenWebUI Reference (REST API, server-side tool calling, saved chats, user-scoped/endpoint-restricted API keys): <https://docs.openwebui.com/reference/>

---

## 5. composeyourself Deployment Sketch

### Service Shape

**Interface Host (sweetpaintedlady — CPX21):**

```yaml
# docker-compose.sweetpaintedlady.yml (overlay)
services:
  openwebui:
    image: ghcr.io/open-webui/open-webui:v0.11.0
    environment:
      - ENABLE_WEB_SEARCH=True
      - WEB_SEARCH_ENGINE=searxng
      - SEARXNG_QUERY_URL=http://searxng:8080/search?q=<query>
      - ENABLE_AUTOMATIONS=True
      - ENABLE_SUBAGENTS=True
      - ENABLE_USER_WEBHOOKS=True
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
      # ... existing env vars
    volumes:
      - openwebui_data:/app/backend/data
    # ... existing labels for Caddy + Authelia OIDC

  searxng:
    image: docker.io/searxng/searxng:latest
    environment:
      - SEARXNG_BASE_URL=https://${DOMAIN}/searxng/
    volumes:
      - searxng_data:/etc/searxng
    # ... cap_drop, logging as per existing SearXNG setup
```

**Worker Host (rocketman — Lenovo home desktop, x86-64, 4 threads / 16 GB RAM, Ubuntu 24.04):**

```yaml
# docker-compose.rocketman.yml (overlay)
services:
  n8n-main:
    image: docker.n8n.io/n8nio/n8n:2.25.7
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-postgres
      - DB_POSTGRESDB_USER=${N8N_DB_USER}
      - DB_POSTGRESDB_PASSWORD=${N8N_DB_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - EXECUTIONS_MODE=queue
      - GENERIC_TIMEZONE=${TIMEZONE}
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on: [n8n-postgres, n8n-redis]

  n8n-worker:
    image: docker.n8n.io/n8nio/n8n:2.25.7
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-postgres
      - DB_POSTGRESDB_USER=${N8N_DB_USER}
      - DB_POSTGRESDB_PASSWORD=${N8N_DB_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - EXECUTIONS_MODE=queue
    depends_on: [n8n-postgres, n8n-redis]

  n8n-postgres:
    image: postgres:16
    volumes: [n8n_pg_data:/var/lib/postgresql/data]

  n8n-redis:
    image: redis:7-alpine
    volumes: [n8n_redis_data:/data]

  # Task runners for code execution isolation (n8n 2.0+)
  n8n-runners:
    image: docker.n8n.io/n8nio/runners:2.25.7
    environment:
      - N8N_RUNNERS_TASK_BROKER_URI=http://n8n-main:5679
      - N8N_RUNNERS_AUTH_TOKEN=${N8N_RUNNERS_AUTH_TOKEN}
    depends_on: [n8n-main]
```

### Authelia Wiring

- **OpenWebUI:** Already behind Authelia OIDC SSO. No change needed.
- **n8n:** Expose n8n-main behind Authelia at `n8n.${DOMAIN}` (or `sweetpaintedlady` IP if only accessed over Tailscale). Authelia handles authentication; n8n's internal user management is secondary (single user). Alternatively, access n8n only over Tailscale without Authelia if the tailnet is trusted.
- **Inter-service communication:** OpenWebUI on the Interface Host calls n8n on the Worker Host over Tailscale (n8n's webhook URL for triggering Background Goal workflows). n8n calls the `announcements` Discord webhook also over Tailscale.

### Interface Host vs Worker Host Split

| Responsibility | Runs On | Why |
|---------------|---------|-----|
| OpenWebUI web UI + API | Interface Host (CPX21) | Must be publicly reachable behind Caddy + Authelia |
| SearXNG search engine | Interface Host (CPX21) | Low resource usage; co-located with OpenWebUI for low-latency search |
| OpenWebUI Automations (lightweight) | Interface Host (CPX21) | Simple scheduled prompts that call models; runs in OpenWebUI's background worker loop |
| n8n main (UI + webhook receiver) | Worker Host (rocketman) | Queue mode main instance; handles workflow editing and webhook triggers |
| n8n worker (workflow execution) | Worker Host (rocketman) | Heavy work: browser automation, multi-step research, git commits, API calls |
| n8n PostgreSQL + Redis | Worker Host (rocketman) | Persistence for n8n workflows and queue |
| n8n task runners | Worker Host (rocketman) | Isolated code execution for n8n Code nodes |
| `announcements` Discord webhook | Worker Host (rocketman, existing) | Already on rocketman; reachable over Tailscale |

**Resource note:** rocketman is a Lenovo desktop with 16 GB RAM — the queue-mode
n8n stack (~5 containers) fits comfortably alongside the existing
yt-dlp/announcements/immich/SigNoz services, so the "Pi headroom" concern does
not apply. The 4 GB CPX21 Interface Host stays lean: OpenWebUI + SearXNG only.

### Background Goal Flow (canonical example)

*"Check every Saturday if https://kpe.utoronto.ca/child-youth/junior-blues is opening registration in the next two weeks. Create a calendar event for the registration date, and message me on discord."*

1. **Trigger:** n8n Schedule Trigger (cron: `0 9 * * 6` — Saturday 9 AM).
2. **Web check:** n8n HTTP Request node fetches the page → AI Agent node analyzes for registration dates (using SearXNG or Brave Search for broader context if needed).
3. **Decision:** If registration is opening within two weeks:
   - n8n HTTP Request to GitHub API → commit an ICS file to Zettelkasten (or use `gh` CLI via Code node).
   - n8n Discord node → send message to `announcements` webhook.
4. **If nothing found:** n8n silently completes (no notification) or sends a heartbeat ("checked, nothing new").

This workflow lives as a version-controlled n8n JSON import in composeyourself, triggered by n8n's scheduler on the Worker Host.

### Zettelkasten Git Tool (for OpenWebUI-native writes)

A Workspace Tool (Python) that:
1. Receives markdown content + title from the model.
2. Generates filename `YYYYMMDDHHMMSS_snake_case_title.md`.
3. Uses `gh` CLI (available in the OpenWebUI container or via a sidecar) to commit to `aaronromeo/zettelkasten` on `main`.
4. Returns the commit URL to the model.

This tool is configured as code in the composeyourself repo (Tool JSON exported and committed), solving R6 for lightweight writes (research summaries, notes) that originate from chat.

---

## Summary

| Candidate | Verdict |
|-----------|---------|
| OpenWebUI v0.11.0 (upgrade only) | **Recommended base** — clears R1–R5, R7–R9, R11–R13 natively; gaps in R6 (git) and heavy Background Goals |
| OpenWebUI v0.11.0 + n8n sidecar | **Recommended full stack** — n8n fills R6 (GitHub node) and heavy Background Goals on Worker Host |
| Dify v1.16.x | Rejected — 15+ containers too heavy for CPX21; no mobile-first chat UI; no chat export path from webui.db |
| Flowise v3.x | Rejected — no native scheduling; workflow-builder UI, not a chat interface |
| Langflow v1.11.x | Rejected — no native scheduling; no mobile chat UI; workflow-builder focus |
