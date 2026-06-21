# Plan: Persist OpenWebUI default model + presets as code (Strategy B)

## Goal

Make two OpenWebUI settings reproducible / version-controlled rather than
clicked into the admin UI:

1. **Default model for new chats** → `anthropic/claude-sonnet-4.6`
2. **Named presets** (custom "Models" wrapping a base model + system prompt):
   - `Cheap` → base `qwen/qwen3-coder`
   - `Deep`  → base `anthropic/claude-opus-4.8`

Strategy chosen: **B — keep `ENABLE_PERSISTENT_CONFIG=true` (UI stays editable),
seed the default model via a committed `config.json`, and seed presets via a
deploy-time call to the OpenWebUI `/api/v1/models/import` API.**

Deployment target: `sweetpaintedlady` (DigitalOcean VPS), compose file
`docker-compose.sweetpaintedlady.yml`, data bind-mounted at
`./services/agenticui:/app/backend/data`.

---

## Background — verified facts (open-webui v0.9.2 source)

These drive every design decision below. All confirmed against the v0.9.2 tag.

- **`DEFAULT_MODELS` is a `PersistentConfig`** (`ui.default_models`). On first
  boot the env value seeds the DB; **on every later boot the DB value wins and
  the env var is ignored.** So the env var alone is not reproducible.
- **`config.json` seed mechanism** (`config.py` startup): if
  `/app/backend/data/config.json` exists, OWUI loads it into the DB **and then
  renames it to `old_config.json`**. This applies the config once per placement
  — exactly what we want for deploy-time reproducibility, and it does NOT wipe
  other UI config (unlike `ENABLE_PERSISTENT_CONFIG=false`).
- **Presets live in the `model` table**, not in config and not settable by env.
  They must be created via API (or DB insert).
- **`POST /api/v1/models/import`** (body `{"models": [ ... ]}`) **upserts by
  `id`** → idempotent, safe to re-run on every deploy. (`POST /create` errors on
  duplicate id, so import is the correct choice.)
- **System prompt for a preset lives at `params.system`** (`ModelParams` has
  `extra='allow'`). Temperature etc. also go in `params`.
- **Auth:** import requires an authenticated admin. An OpenWebUI admin **API key**
  (`sk-...`) sent as `Authorization: Bearer sk-...` satisfies it, **but only if
  `ENABLE_API_KEYS=true`** (checked via `request.state.enable_api_keys`).
- **Readiness endpoint:** `GET /api/version` (already used by the compose
  healthcheck, line 63). Poll this before importing.
- **Login is OAuth-only** (`ENABLE_LOGIN_FORM=false`, `ENABLE_PASSWORD_AUTH=false`),
  so password login for the script is not viable → API key is the chosen auth.

---

## Decisions (confirmed with user)

| Question | Decision |
|---|---|
| Strategy | B (config.json + API import; keep persistent config on) |
| Preset auth | Admin **API key in `.env`** (`OPENWEBUI_API_KEY`) |
| config.json delivery | `generate_config.sh` copies committed file into data dir before `up` |
| Presets | Sonnet default + `Cheap` (qwen3-coder) + `Deep` (opus-4.8) |
| webui.db persistence | **In scope** — verify it lands in `./services/agenticui`, fix if not |

---

## Prerequisite — verify webui.db persistence (do FIRST)

The data dir `./services/agenticui` currently contains only `.keep`. Either the
live instance writes its DB elsewhere (bind mount not effective) or the local
checkout simply lacks runtime data. **Nothing below persists if the bind mount
isn't capturing `webui.db`.**

Steps (on the live `sweetpaintedlady` host):
1. With the stack running, check the host path:
   `ls -la services/agenticui/` — expect `webui.db`, `uploads/`, `cache/`.
2. And inside the container: `docker compose ... exec openwebui ls -la /app/backend/data`.
3. If `webui.db` is present on the host → persistence is good, proceed.
4. If absent on host but present in container → the bind mount is being shadowed
   (e.g. anonymous volume, wrong path, or SELinux/permission). Fix before
   continuing: confirm the `volumes:` entry resolves to the intended host dir and
   that the `open-webui` container user (uid 0 / root in this image) can write it.

Acceptance: admin-made UI changes survive `docker compose down && up -d`.

---

## Repository layout to add

```
services/
  agenticui/                 # bind-mounted runtime data (gitignored except .keep)
  agenticui-config/          # NEW — committed, version-controlled source of truth
    config.json              # seeds ui.default_models
    models.json              # the {"models":[...]} import payload (Cheap/Deep)
    prompts/                 # OPTIONAL: long system prompts kept readable
      cheap.md
      deep.md
scripts/
  seed-openwebui.sh          # NEW — deploy-time import of models.json
docs/plans/
  OPENWEBUI_DEFAULTS_AS_CODE.md  # this file
```

> Note: keep committed config under `agenticui-config/` (NOT inside the
> bind-mounted `agenticui/`), so OWUI's rename-to-`old_config.json` never mutates
> a tracked file.

---

## Step 1 — Committed `config.json` (default model)

`services/agenticui-config/config.json`:

```json
{
  "version": 0,
  "ui": {
    "default_models": "anthropic/claude-sonnet-4.6"
  }
}
```

Notes:
- `default_models` is a string (model id). For multiple defaults OWUI accepts a
  comma-separated string.
- Optional: also seed `ui.default_pinned_models` and `ui.prompt_suggestions`
  here later if desired — same file, same import path.

---

## Step 2 — Deliver config.json on deploy (`generate_config.sh`)

Add a step in `generate_config.sh` (the templating stage, runs before
`docker compose up` in both `deploy.sh` and `update.sh`):

- Ensure `services/agenticui/` exists.
- Copy `services/agenticui-config/config.json` →
  `services/agenticui/config.json` **only if** it differs / fresh deploy desired.
- Because OWUI renames it to `old_config.json` after import, re-copying on each
  deploy re-applies the declared default model. This is intentional and
  idempotent (it just re-asserts the default; it does not clobber unrelated UI
  config because the JSON only contains the `ui.default_models` key).

Open sub-decision (call out in implementation, default = re-apply every deploy):
- **Re-apply every deploy** (copy unconditionally): default model is always
  reset to the declared value on deploy. Predictable/declarative. ← recommended
- **First-deploy only** (copy only if neither `config.json` nor `old_config.json`
  present): lets an admin override the default in the UI and keep it. Less
  strictly declarative.

---

## Step 3 — Enable API keys + add admin key to env

In `docker-compose.sweetpaintedlady.yml` (openwebui `environment:`), add:

```yaml
      - ENABLE_API_KEYS=true
```

In `.env` (and document in `.env.example`):

```
# OpenWebUI admin API key (sk-...), used by scripts/seed-openwebui.sh to import
# model presets at deploy time. Generate once in the UI: Settings > Account >
# API Keys (must be an account with an openwebui-admin role).
OPENWEBUI_API_KEY=
```

One-time bootstrap (manual, documented in README/SERVICES.md):
1. Deploy with `ENABLE_API_KEYS=true`.
2. Log in via Authelia as an `openwebui-admin` user.
3. Settings → Account → create API key (`sk-...`).
4. Put it in `.env` as `OPENWEBUI_API_KEY`.
5. Subsequent deploys auto-seed presets.

> The seed step must **no-op gracefully** if `OPENWEBUI_API_KEY` is empty
> (first deploy before the key exists) — log a warning and skip, don't fail the
> deploy.

---

## Step 4 — Committed `models.json` (presets)

`services/agenticui-config/models.json` — payload for `/api/v1/models/import`.
Shape per the v0.9.2 `ModelForm` (`id`, `name`, `base_model_id`, `meta`,
`params`, `is_active`); system prompt at `params.system`:

```json
{
  "models": [
    {
      "id": "cheap",
      "name": "Cheap (Qwen3 Coder)",
      "base_model_id": "qwen/qwen3-coder",
      "is_active": true,
      "meta": {
        "description": "Fast, cheap executor for routine coding/grunt work.",
        "profile_image_url": "/static/favicon.png"
      },
      "params": {
        "system": "You are a fast, efficient coding assistant for routine tasks. Apply changes directly and concisely. Do not over-explain."
      }
    },
    {
      "id": "deep",
      "name": "Deep (Claude Opus 4.8)",
      "base_model_id": "anthropic/claude-opus-4.8",
      "is_active": true,
      "meta": {
        "description": "High-reasoning model for architecture, debugging, and hard problems.",
        "profile_image_url": "/static/favicon.png"
      },
      "params": {
        "system": "You are a senior staff engineer. Reason carefully about architecture, edge cases, and tradeoffs before answering."
      }
    }
  ]
}
```

Notes:
- `base_model_id` must match an OpenRouter model id exactly as it appears in the
  OWUI model list (OpenAI-compatible connection → `qwen/qwen3-coder`,
  `anthropic/claude-opus-4.8`). Verify these ids resolve in the running instance.
- Long prompts can be stored in `agenticui-config/prompts/*.md` and assembled by
  `seed-openwebui.sh` with `jq` if inlining gets unwieldy. Optional.
- Import upserts by `id`, so editing this file + redeploy updates the presets.

---

## Step 5 — Seed script (`scripts/seed-openwebui.sh`)

Behavior:
1. Load `.env`. If `OPENWEBUI_API_KEY` empty → log warning, `exit 0` (skip).
2. Determine OWUI base URL. Script runs on the host; OWUI has no published host
   port (only `expose: 8080` on the `cys-service` network). Options:
   - **Run the curl inside the network** via a one-shot container on
     `cys-service` (`docker compose ... run --rm ... ` or
     `docker run --network <project>_cys-service curlimages/curl ...`), targeting
     `http://openwebui:8080`. ← recommended (no host port needed)
   - Or temporarily address it through Caddy at `https://${SUBDOMAIN}.${DOMAIN}`
     (goes through Authelia forward-auth — likely blocks API key; avoid).
3. Poll readiness: `GET http://openwebui:8080/api/version` until 200 (timeout ~60s).
4. `POST http://openwebui:8080/api/v1/models/import`
   with `Authorization: Bearer ${OPENWEBUI_API_KEY}`,
   `Content-Type: application/json`, body = `@services/agenticui-config/models.json`.
5. Assert HTTP 200 and body `true`; on non-200 print response and `exit 1`.

Idempotency: safe to run on every deploy (upsert by id).

Network detail to resolve during implementation: the actual docker network name
(`<project>_cys-service`). Prefer `docker compose ... run` so compose resolves the
network/service name automatically rather than hardcoding.

---

## Step 6 — Wire into deploy/update scripts

In `deploy.sh` and `update.sh`, **after** `docker compose ... up -d`:

```bash
echo "🌱 Seeding OpenWebUI presets..."
chmod +x scripts/seed-openwebui.sh
./scripts/seed-openwebui.sh "$HOST" || echo "⚠️ Preset seeding skipped/failed (non-fatal)"
```

- Only meaningful for `sweetpaintedlady`; the script can early-exit for other hosts.
- Non-fatal: a missing API key on first deploy must not break the deploy.
- `config.json` copy happens earlier inside `generate_config.sh` (Step 2), so it's
  already in place before `up`.

---

## Step 7 — Docs + env example

- `.env.example`: add `OPENWEBUI_API_KEY=` with the bootstrap comment.
- `docker-compose.sweetpaintedlady.yml`: add a comment near the openwebui service
  explaining the PersistentConfig gotcha, the `config.json` seed, and
  `ENABLE_API_KEYS`.
- `SERVICES.md` / `README.md`: document the one-time API-key bootstrap and how to
  edit `agenticui-config/{config.json,models.json}` to change defaults/presets.
- `.gitignore`: confirm `services/agenticui/*` is ignored (except `.keep`) and that
  the new `services/agenticui-config/` is tracked.

---

## Acceptance criteria

1. Fresh deploy with `OPENWEBUI_API_KEY` set → new chats default to
   `anthropic/claude-sonnet-4.6`, and `Cheap` + `Deep` presets appear in the model
   picker.
2. Re-running `deploy.sh`/`update.sh` is idempotent (no duplicate presets, no
   errors; presets reflect current `models.json`).
3. Admin UI config changes (other than the seeded default model) survive restarts
   (persistent config still on; webui.db persists).
4. First deploy with empty `OPENWEBUI_API_KEY` completes without failing (preset
   seeding skipped with a warning).
5. Editing `models.json` + redeploy updates the existing presets in place.

---

## Risks / gotchas

- **No host port for OWUI** → seed script must run inside the `cys-service`
  network. Resolve exact network/service addressing during implementation.
- **API key bootstrap is manual & one-time** → unavoidable given OAuth-only login.
  Document clearly; make the script skip gracefully until the key exists.
- **`config.json` is consumed (renamed) on boot** → must re-copy each deploy if we
  want the default re-asserted; chosen behavior is re-apply (Step 2).
- **`base_model_id` mismatch** → if the OpenRouter id isn't present/active in the
  instance, the preset will reference a missing base model. Verify ids post-deploy.
- **Permissions on bind mount** → image runs as root; ensure host dir is writable
  so `config.json` → `old_config.json` rename succeeds.
```