# Handoff — Assistant work (D1 complete + deployed; D2 not designed)

_Date: 2026-08-18. Updated at the close of the D1 deploy._

## Where things stand

**Deliverable 1 (OpenWebUI upgrade + SearXNG + env-authoritative config) is complete and live on sweetpaintedlady** as of 2026-08-18. OpenWebUI v0.11.0 is healthy; the new self-hosted SearXNG search engine is healthy and returning real JSON results; the env-authoritative config (`ENABLE_PERSISTENT_CONFIG=False`) is in place. User-verified acceptance tests: **T5** (determinism) and **T6** (pre-flight). T1–T4 (UI-driven: visible `search_web` tool calls, deep research, sub-agent fan-out, automation creation) were not browser-tested — the user accepted D1 complete without them. Re-test them in the browser at any time if you want full coverage.

**Deliverable 2 (n8n deployment + OWUI integration) has NOT been designed.** When ready, invoke `brainstorming` for a fresh D2 cycle.

## Read these first (in order)

1. `CONTEXT.md` — glossary; use its terms verbatim.
2. `2026-08-16-assistant-research-brief.md` — requirements R1–R13 + the switching bar.
3. `2026-08-16-assistant-research-findings.md` — research + recommendation + interaction patterns + deployment sketch.
4. `../../adr/0001-self-hosted-assistant-only.md` — scope decision.
5. `2026-08-16-owui-upgrade-design.md` — D1 spec (approved + implemented).
6. `../../plans/2026-08-16-owui-upgrade/plan.md` — D1 implementation plan (Tasks 1–6 executed from the workspace; Task 7 host-side deploy + UI tests run on sweetpaintedlady).
7. `2026-08-16-assistant-handoff.md` — this document.

## D1 implementation: what landed (for D2 context)

Eleven commits on `main` between 2026-08-17 and 2026-08-18, all pushed to origin/main. A fresh D2 agent should know the following so it doesn't re-derive them:

- **SearXNG settings template** (`services/searxng-config/settings.yml`) uses `use_default_settings: true` to overlay the upstream defaults; the only override is `search.formats: [html, json]` (required by OWUI — without `json`, SearXNG 403s).
- **The `ultrasecretkey` gotcha:** SearXNG's container entrypoint only runs its own sed-replacement of the `ultrasecretkey` placeholder when settings.yml is **missing** (the template-copy path). Since we bind-mount our own, that sed is skipped and Granian refuses to start with the default key — producing a fatal crash loop. Fix lives in `generate_config.sh` (commits `a88e522` + `0773a2a`): a random `secret_key` is generated at deploy time and sed-replaced into the live settings.yml; the file is written via `docker run -u root alpine` to bypass host permissions (the searxng container, UID 977, ends up owning the bind-mount source dir, so a direct `cp`/`sed` as `dockerops` hits Permission denied).
- **`ENABLE_PERSISTENT_CONFIG=False`** makes the env block in `docker-compose.sweetpaintedlady.yml` authoritative on every boot; Admin UI changes are session-only. Admin Panel → Models default capabilities come from `DEFAULT_MODEL_METADATA` env (explicitly applied even with persistent config disabled — gives `web_search` + `builtin_tools` + `defaultFeatureIds: ["web_search"]` to all models, including raw OpenRouter ones).
- **Sub-agent guardrails 5/3/10** (concurrent / background / iterations per sub-agent) — set via `SUBAGENTS_MAX_*` env. Conservative to protect OpenRouter spend; raise if real usage demands it.
- **No valkey** for SearXNG: our settings leave `limiter: false` and `valkey.url: false` at their defaults, so the limiter / bot-detection feature that needs Valkey is off; the official compose template's valkey service is intentionally omitted.
- **`update.sh` early-exit footgun:** line 62 checks `HEAD == origin/main` and exits if equal. If you manually `git pull` first, update.sh silently no-ops and the deploy never happens. Either let update.sh do its own pull (don't pull manually), or run the post-check steps manually: `make sync-submodules` → `./generate_config.sh` → `docker compose ... config` → `docker compose ... pull --ignore-buildable` → `docker compose ... build` → `CYS_SKIP_LOCK=1 ./restart.sh <host>`.
- **`update.sh` not executable in git** — `5244ecf` marks it `+x`; future pulls keep it executable.

## D2's open decisions

(These were the open decisions at the end of the brainstorming session; the recommendations from that session are in parentheses and still stand as a starting point.)

- **Who holds git credentials** — recommend: n8n's GitHub node (not the OWUI container). Keeps tokens out of the chat container entirely.
- **v1 Background Goal list** — recommend: the Junior Blues Saturday check only; add more later.
- **Heartbeat vs silent on negative checks** — user undecided; propose a default in the D2 brainstorm.
- **Shared vault vs dedicated agent vault** — recommend: shared, using existing Zettelkasten naming conventions (`YYYYMMDDHHMMSS_snake_case.md`).
- **The `announcements` service API contract is UNKNOWN.** Its submodule (`services/announcements`) is uninitialized in this checkout. `make init-submodules` (private repos, SSH) and read the service before designing D2's Notification path. Or, if a background agent investigates, use the `research` skill.
- **The user's working-style preferences** (carry forward): one question at a time, each with a concrete recommendation they can approve in a word; no large unstructured question dumps; state explicitly who does what before any multi-step work.

## Suggested skills

- **brainstorming** — next, when starting the D2 design cycle.
- **research** — if D2 wants the announcements contract or n8n specifics investigated by a background agent first.
- **writing-plans** — after the D2 spec is approved, to produce the D2 implementation plan.
- **verification-before-completion** — during D2 implementation; the infra repo's only local sanity check is `docker compose -f ... -f ... config`.
- **test-driven-development** — not directly applicable to this infra repo (no test suite), but D2 can still adopt the TDD-adapted discipline used in D1: each task ends with a verification step using compose config + `bash -n` + grep / yaml / python assertions.

## Environment facts

- This session runs on **rocketman** — the Worker Host, a Lenovo home desktop (x86-64, 16 GB RAM, Ubuntu 24.04). `gh` is authenticated and can read the private `aaronromeo/zettelkasten` repo.
- **SSH to sweetpaintedlady**: `ssh -i ~/.ssh/Hetzner dockerops@agentic.overachieverlabs.com` (Hetzner CPX21 VPS; the host's local hostname is `morph-production`, but the repo's canonical name is **sweetpaintedlady** — use that in operational prose).
- Deploys run on the target host (`/opt/docker/composeyourself`, as `dockerops`) — never run `docker compose up` from this workspace checkout. The searxng settings copy, the Authelia keypair regeneration, etc., all happen via `generate_config.sh` + `restart.sh` / `update.sh` on the host.
- The agent has direct SSH access to sweetpaintedlady (verified in this session) and can do the mechanical deploy + restart + mechanical verification (version, SearXNG JSON query, container `ps`). UI acceptance tests still require the user to click in a browser.

## Known leftover items (not blocking D1; not in scope for the Assistant initiative)

- **otelcol-agent on sweetpaintedlady** is in a restart loop (`Restarting (1)`). Pre-existing, unrelated to D1. Worth investigating as a separate maintenance task; check `docker compose ... logs otelcol-agent` for the cause.
- **deliberately left stale** (do not "fix" without asking): SERVICES.md title/intro, the deploy/update/restart.sh echo strings, the docker-compose.rocketman.yml header comment, and the yt-dlp / signoz setup notes still say "Raspberry Pi". Historical `docs/plans/*` are dated records — do not rewrite them.

## Redaction note

No secrets appear in this document or the session artifacts; `.env` values and API keys were never part of the work.
