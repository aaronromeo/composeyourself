# Handoff — Assistant work (D1 designed, awaiting spec review)

_Date: 2026-08-16. Written at the close of the D1 brainstorming session._

## Where things stand

The Assistant exploration (successor to the OpenWebUI + OpenRouter setup) has
completed three stages: requirements grilling → background research → approved
design for Deliverable 1. All artifacts live in this repo, committed and pushed
to `main`; the working tree was clean at handoff.

**Pipeline position: the D1 design spec is written and awaits user review.**
On approval, invoke `writing-plans` for D1. D2 (n8n deployment + OWUI
integration) has NOT been designed — it gets its own brainstorm → spec → plan
cycle after D1 ships.

## Read these first (in order)

1. `docs/specs/assistant/CONTEXT.md` — glossary; use its terms verbatim.
2. `docs/specs/assistant/2026-08-16-assistant-research-brief.md` — requirements
   R1–R13 and the verbatim switching bar.
3. `docs/specs/assistant/2026-08-16-assistant-research-findings.md` — candidate
   evaluation, recommendation (OWUI v0.11.0 + n8n sidecar), interaction
   patterns, deployment sketch.
4. `docs/adr/0001-self-hosted-assistant-only.md` — hard scope constraint.
5. `docs/specs/assistant/2026-08-16-owui-upgrade-design.md` — the D1 spec under
   review (upgrade v0.9.6 → v0.11.0, self-hosted SearXNG, permanent
   `ENABLE_PERSISTENT_CONFIG=False`, sub-agent guardrails 5/3/10, upgrade drill,
   acceptance tests T1–T6).

## Session context not captured in the artifacts

- **Two deliverables, sequenced.** D1 = OWUI upgrade (spec above); D2 = n8n +
  integration (not yet designed). Technically independent; the user wants this
  order so each deploy stays small and verifiable.
- **User's working-style preferences** (hard-won this session): one question at
  a time, each with a concrete recommendation they can approve in a word; no
  large unstructured question dumps; state explicitly who does what before any
  multi-step work.
- **D2's open decisions** (recommendation from this session in parentheses):
  who holds git credentials (n8n's GitHub node, not the OWUI container); v1
  Background Goal list (the Junior Blues Saturday check only); heartbeat vs
  silent on negative checks (user undecided — propose a default); shared vault
  vs dedicated agent vault (shared, using existing naming conventions).
- **The `announcements` service API contract is UNKNOWN.** Its submodule is
  uninitialized in this checkout. `make init-submodules` (private repos, SSH)
  and read the service before designing D2's Notification path.
- **Environment facts.** This session ran ON rocketman — the Worker Host, a
  Lenovo desktop (x86-64, 16 GB RAM, Ubuntu 24.04), not a Raspberry Pi. `gh` is
  authenticated and can read the private `aaronromeo/zettelkasten` repo.
  Deploys run on the target host (`/opt/docker/composeyourself`, as
  `dockerops`) — never run `docker compose up` from this workspace checkout.
- **Deliberately left stale** (do not "fix" without asking): SERVICES.md
  title/intro, the deploy/update/restart.sh echo strings, the
  docker-compose.rocketman.yml header comment, and the yt-dlp/signoz setup
  notes still say "Raspberry Pi". Historical `docs/plans/*` are dated records —
  do not rewrite them.

## Suggested skills

- **writing-plans** — immediately, once the user approves the D1 spec.
- **verification-before-completion** — during implementation; note this is an
  infra repo, so `docker compose config` is the only local sanity check.
- **brainstorming** — when starting the D2 design cycle.
- **research** — if D2 wants the announcements contract or n8n specifics
  investigated by a background agent first.

## Redaction note

No secrets appear in this document or the session artifacts; `.env` values and
API keys were never part of the work.
