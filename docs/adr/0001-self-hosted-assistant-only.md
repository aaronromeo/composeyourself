# Self-hosted Assistant only

The successor to the OpenWebUI setup must be self-hosted and deployable through
composeyourself; hosted assistant subscriptions (ChatGPT/Claude/Gemini apps) are
excluded as the core product, though hosted model APIs remain in scope as Model
Backends. The deciding factors: the required integrations live on the user's own
infrastructure (direct commits to the Zettelkasten, the `announcements` Discord
service, the Tailscale Interface/Worker Host split, Authelia), model backends
must stay swappable at near-zero marginal cost, and the data must remain
exportable at all times.

## Considered options

- **Hosted assistant subscription as the core** — rejected. Best-in-class Deep
  Research out of the box, but no write-path into the self-hosted Zettelkasten
  and announcements service, model/vendor lock-in, recurring per-seat cost, and
  weaker exit-ability.

## Consequences

- Encoded as hard requirement R10 in
  `docs/specs/assistant/2026-08-16-assistant-research-brief.md`; any candidate
  that can't deploy via Docker Compose behind Authelia is out of scope.
- Deep Research quality must come from configuration (search engine, agent
  tooling), not a vendor bundle.
