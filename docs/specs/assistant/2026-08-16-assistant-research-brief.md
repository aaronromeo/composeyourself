# Research Brief — Successor to the OpenWebUI Setup

_Date: 2026-08-16. Status: requirements gathered, ready to hand to a research agent._

## Purpose

Find the best path forward for the user's personal **Assistant**: today it is
OpenWebUI v0.9.6 + OpenRouter, self-hosted; it no longer meets requirements. This
brief is the complete input for a research agent tasked with evaluating
candidates and recommending one.

**Read [`CONTEXT.md`](./CONTEXT.md) first.** Capitalized terms in this brief
(Orchestration, Background Goal, Deep Research, Notification, Zettelkasten, …)
are defined there and are used verbatim. Do not substitute your own
interpretations.

## Current state

- **OpenWebUI v0.9.6** fronting **OpenRouter**, running on **sweetpaintedlady**
  (Hetzner CPX21: 3 vCPU / 4 GB RAM), behind Caddy + Authelia (OIDC SSO).
  Managed as code in the `composeyourself` repo (compose overlays, generated
  configs, seeded model presets).
- **rocketman** (Lenovo home desktop, x86-64 — 4 threads / 16 GB RAM, Ubuntu
  24.04) runs supporting services, reachable over **Tailscale** — including the `announcements` service (Discord webhook,
  Tailscale :8091) which is today's **Notification** path.
- Default model `anthropic/claude-sonnet-4.6`; Cheap/Deep presets
  (`qwen/qwen3-coder`, `anthropic/claude-opus-4.8`). User separately runs
  **OpenCode** (Go/Zen subscriptions) on their workstation — code implementation
  is OpenCode's job, not the Assistant's.
- A year of chat history lives in OpenWebUI's `webui.db`.

### The precipitating incident

The user toggled web search in the OpenWebUI admin UI and asked Opus 4.8 to
research mesh WiFi. The model truthfully reported it had no search tool and no
results in context — the admin toggle had never reached the model. No search
engine is configured anywhere in the as-code config. The requirement this
crystallized:

> **Tool use must be platform-executed, verifiable, and configured as code —
> never model-asserted.**

The research was eventually done by the user's agentic tooling and filed in the
Zettelkasten — the workflow the Assistant should have owned.

## Hard requirements (v1)

- **R1 — Search-and-Summarize.** Platform-executed web search in chat, with
  results visibly grounded (citations/links), configured as code — not a UI
  toggle living in a database.
- **R2 — Deep Research.** Long-running, multi-source web investigations
  producing a cited report.
- **R3 — Orchestration.** A lead agent decomposes a task and delegates to
  specialized sub-agents within a single request.
- **R4 — Background Goals with Triggers.** Objectives assigned once, pursued
  autonomously on a schedule, reporting back. Canonical example, verbatim:
  *"Check every Saturday if https://kpe.utoronto.ca/child-youth/junior-blues is
  opening registration in the next two weeks. Create a calendar event for the
  registration date, and message me on discord."* — this single example
  exercises scheduling, semantic web-page monitoring, calendar output, and
  Notification.
- **R5 — Notifications.** Proactive delivery outside the chat UI, via the
  existing `announcements` Discord webhook service (or an equivalent Discord
  mechanism).
- **R6 — Zettelkasten write-path.** Research output is saved to the Zettelkasten
  (private GitHub repo, Obsidian vault). Notes are flat files named
  `YYYYMMDDHHMMSS_snake_case_title.md`; attachments in `media/`; templates in
  `templates/`. Direct commits to `main` are permitted; `gh`/git credentials
  available. (The user can provide a dedicated vault if separation is warranted.)
- **R7 — Dual-format output.** Every research artifact must be consumable by a
  human *and* ingestible by another agent (a markdown note satisfies both).
- **R8 — Skills.** Reusable prompt/workflow packages invocable by name, to avoid
  duplicating instructions (the user runs superpowers-style skills in OpenCode
  today, including skill-driven brainstorming/spec sessions like the one that
  produced this brief).
- **R9 — Model-backend agnostic.** Must accept OpenAI-compatible endpoints
  (OpenRouter, OpenCode Go/Zen, …). Optimize for near-zero marginal cost at high
  capability (e.g. Kimi K3); no single-vendor model lock-in.
- **R10 — Self-hosted deployment.** Interface Host fronted by Authelia on the
  CPX21 class edge VPS; heavy work (browser automation, schedulers, larger
  services) offloadable to a Worker Host (a home machine — today rocketman)
  over Tailscale. Must fit
  `composeyourself` idioms: Docker Compose overlays, generated/committed
  config, no hand-clicked state.
- **R11 — Mobile web UI.** The user chats from a phone browser today.
- **R12 — Single user.** No multi-user/tenant features required; auth via the
  existing Authelia pattern.
- **R13 — Exit-ability.** Whatever is chosen, the user's data (chats, settings,
  artifacts) must be exportable at any later date. This applies even in the
  "keep OpenWebUI" outcome.

## Nice-to-have (not v1)

- **Mailbox** integration — Fastmail, **read-only** scope.
- **Calendar** writes — Google Calendar. Delivery of an **ICS file** (via
  Notification or email) is an acceptable substitute for direct writes.

## Conditional requirements

- **If** the recommendation replaces OpenWebUI: migrate the year of chat history
  in `webui.db`. If staying on OpenWebUI, no migration needed.

## Non-goals

- **Code implementation** — OpenCode owns it. (The Assistant *is* used to
  research coding projects and run brainstorming/spec skills; it just never
  writes the code.)
- Image generation, voice — not required.
- Multi-user support.

## The switching bar (verbatim)

> "I'll only switch if it can provide processes which can search the web, run
> multiple agents for search in the background, use prompts/skills to reduce
> duplication and export the summaries so they can either be consumed as a human
> or ingested by a different agent."

**"Keep OpenWebUI and extend it"** (pipelines, functions, MCP tools, properly
configured search, an automation sidecar) **is a valid outcome** — provided it
clears the bar and preserves R13.

## Constraints on candidates

- Self-hosted only. Hosted assistant subscriptions (ChatGPT/Claude/Gemini apps)
  as the *core* are out of scope. (Hosted model APIs as Model Backends are in
  scope per R9.)
- Must operate within: CPX21 edge (3 vCPU / 4 GB — tight; already runs Caddy,
  Authelia, OpenWebUI, otelcol) + a home Worker Host, Docker Compose,
  Tailscale.
- Deployment must be expressible as code in `composeyourself`.

## Starting points for the search (non-exhaustive)

- **Keep + extend:** OpenWebUI web search done properly as code (engine, e.g.
  self-hosted SearXNG), pipelines/functions/MCP, plus a self-hosted automation
  engine for Background Goals (e.g. n8n-class tools).
- **Replace:** self-hosted agentic chat/assistant platforms with native tool
  use, sub-agents, and scheduled/background execution.
- Evaluate categories, then specific candidates; the list above is a seed, not
  a shortlist.

## Deliverable expected from the research agent

1. Candidate longlist with one-paragraph summaries and sources.
2. Shortlist scored against R1–R13 in a matrix (cite evidence per cell; mark
   unknowns honestly).
3. A recommendation with rationale, including migration cost and how
   exit-ability (R13) is preserved.
4. A sketch of how the recommendation deploys into `composeyourself` (compose
   service shape, Authelia wiring, what runs on the Interface vs Worker Host).

## Open questions (do not block research)

- Background Goal reporting style: silent-unless-action vs. heartbeat — user is
  undecided; a Discord message either way is acceptable.
- Whether agent output gets its own dedicated vault or shares the main
  Zettelkasten.
