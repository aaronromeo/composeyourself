# AGENTS.md

Infra repo, not an app: multi-host Docker Compose deployment for a self-hosted stack.
No application code lives here except config templates. There is no build/test/lint
step for this repo itself.

## Hosts & compose file chain

Two hosts, selected by argument to the scripts — never run `docker compose up` with a
single file:

- **rocketman** (Raspberry Pi): `docker-compose.yml -f docker-compose.rocketman.yml -f services/signoz/docker-compose.signoz.yml`
- **sweetpaintedlady** (DigitalOcean VPS): `docker-compose.yml -f docker-compose.sweetpaintedlady.yml`

Key scripts (run on the target host in `/opt/docker/composeyourself`, as `dockerops`):

- `./deploy.sh <host>` — first deploy. Runs `make sync-submodules`, `generate_config.sh`,
  then `docker compose ... down && build --no-cache && up -d`.
- `./update.sh <host>` — incremental update. Skips if git already up to date, validates
  `docker compose ... config` before the rebuild, pulls prebuilt images, then hands the
  stack down/up off to `restart.sh`.
- `./restart.sh <host>` — take the stack down and bring it back up (down + `up -d` +
  preset seeding) without touching git, config generation, or image builds. Works when
  git is up to date (where `update.sh` early-exits). `update.sh` calls it internally
  with `CYS_SKIP_LOCK=1` since it already holds the shared update lock.
- `./generate_config.sh` — regenerates configs from templates. Requires `DOMAIN` in `.env`
  **even on rocketman** (which never runs Authelia/Caddy), or it exits 1.

The only sanity check available for local edits is `docker compose -f <chain> config`
(runs before rebuilds in `update.sh` and before restarts in `restart.sh`).

The systemd units (`composeyourself-*.service`) run base + host overlay; the rocketman
unit also includes the signoz overlay, so boot-time start / `systemctl restart` brings
up the full stack including observability.

## Submodules

`services/announcements`, `services/yt-dlp`, `services/swole` are private (SSH) git
submodules. Empty submodule dirs in a fresh checkout are normal — initialize with
`make init-submodules` / `make sync-submodules` (syncs to the pinned commits).
`make update-submodules` advances them to upstream `main` and stages the pointer bump.
A nightly workflow commits submodule bumps directly to `main` (needs `SUBMODULES_PAT`).

## Generated files — never hand-edit

All of the following are produced from committed sources on every deploy and are
gitignored (or regenerated):

- `services/authelia/configuration.yml` — from `configuration.yml.template` (envsubst).
- `services/authelia/users_database.yml` — from `users_database.yml.template`, but only
  on **first** deploy; updates preserve server-side password changes. Edit the template
  or the file on the host, not this checkout.
- `services/authelia/keys/` — OIDC keypair, wiped and regenerated every deploy.
- `services/agenticui/config.json` — copied from `services/agenticui-config/config.json`.
- `.env` — copy of `.env.example`; never commit.

## Open WebUI defaults-as-code

Source of truth is `services/agenticui-config/` (`config.json` = default model,
`models.json` = Cheap/Deep presets). `generate_config.sh` re-copies `config.json` on
every deploy because OWUI renames it to `old_config.json` after importing; the
`DEFAULT_MODELS` env var is only honored on first boot (PersistentConfig gotcha).
Preset seeding (`scripts/seed-openwebui.sh`) requires an `OPENWEBUI_API_KEY` in `.env`
(one-time bootstrap via admin UI); it no-ops gracefully until then.

## Observability (SigNoz / OpenTelemetry)

- The rocketman collector (`services/signoz/`) and the SPL edge collector
  (`services/otelcol-spl/config.yaml`) forward telemetry over Tailscale.
- Collector + schema-migrator versions are pinned by the same env var and must be
  bumped as a pair (`SIGNOZ_OTEL_COLLECTOR_VERSION`); ClickHouse must be ≥25.5.6 for
  that migrator (JSON DDL). Pins and rationale live in `services/signoz/VERSIONS.md`.
- `SIGNOZ_BIND_ADDR` default `0.0.0.0` exposes the SigNoz UI/OTLP on every interface —
  set it to rocketman's Tailscale IP in prod. (yt-dlp no longer collides: it moved to
  host `:8082`.) Same for `TAILNET_BIND_ADDR` (kernel TUN mode no
  longer proxies inbound tailnet connections to `127.0.0.1`). Services that bind a
  tailnet IP gate on the `tailscale` healthcheck (`tailscale ip -4`) via `depends_on:
  condition: service_healthy` — after `down` the tailnet interface is gone until the
  tailscale container re-establishes it, so an ungated bind fails with "cannot assign
  requested address".
- SigNoz data dirs are chowned `1000:1000` and ClickHouse publishes no host port.

## Docs

- `docs/specs/OTEL_SPEC.md` + `docs/plans/OTEL_PLAN.md` — observability design; read
  before touching anything under `services/signoz/` or `services/otelcol-spl/`.
- `docs/plans/OPENWEBUI_DEFAULTS_AS_CODE.md` — Open WebUI defaults-as-code design.
- `docs/specs/` + `docs/plans/` contain dated design docs for each subsystem; read the
  relevant one before changing that area.
- `README.md` is the current overview. `SERVICES.md` is partially stale (bottom half
  describes an old `pi-services`/Cloudflare layout that no longer exists).
