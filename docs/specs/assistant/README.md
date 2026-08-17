# Assistant — exploration docs

Requirements, research, and design for the successor to the OpenWebUI +
OpenRouter setup. Terminology lives in `CONTEXT.md` — read it first; the other
docs use its terms verbatim.

## Execution order

1. **D1 — OpenWebUI upgrade** (v0.9.6 → v0.11.0, self-hosted SearXNG,
   env-authoritative config): `2026-08-16-owui-upgrade-design.md`.
   **Status: awaiting user review**, then `writing-plans`.
2. **D2 — n8n deployment + OWUI integration**: not yet designed. Gets its own
   brainstorm → spec → plan cycle after D1 ships.

## Reading order

1. `CONTEXT.md` — glossary.
2. `2026-08-16-assistant-research-brief.md` — requirements (R1–R13) + the
   switching bar.
3. `2026-08-16-assistant-research-findings.md` — candidate research,
   recommendation, interaction patterns, deployment sketch.
4. `../../adr/0001-self-hosted-assistant-only.md` — the scope decision.
5. `2026-08-16-owui-upgrade-design.md` — the D1 spec (**the document currently
   under review**).
6. `2026-08-16-assistant-handoff.md` — session handoff for a fresh agent
   picking up the work.
