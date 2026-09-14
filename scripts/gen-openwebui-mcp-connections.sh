#!/usr/bin/env bash
# Generates services/agenticui/generated.env (TOOL_SERVER_CONNECTIONS) wiring
# Open WebUI to the self-hosted Google Workspace MCP server (the
# google-workspace-mcp service in docker-compose.sweetpaintedlady.yml).
#
# Called by generate_config.sh on every deploy. No-op (comment-only file) when
# USER_GOOGLE_EMAIL is not set — e.g. on hosts that don't run workspace-mcp.
#
# Design:
#   - The openwebui container reads its signing key from
#     WEBUI_SECRET_KEY_FILE=/app/backend/data/.webui_secret_key (set in
#     docker-compose.sweetpaintedlady.yml; start.sh default would be
#     /app/backend/.webui_secret_key — outside the volume, regenerated on
#     every container recreate, invalidating logins). This script ensures that
#     file exists so the key persists across deploys.
#   - The workspace-mcp server runs its own Google OAuth consent (single-user
#     server OAuth; one token stored server-side, keyed by USER_GOOGLE_EMAIL).
#     Open WebUI connects with auth_type "none": no Authorization header, no
#     per-user OAuth state (verified in open_webui/utils/tools.py v0.11.1,
#     build_tool_server_headers — auth_type 'none' adds no header). So this
#     script no longer builds Fernet blobs or runs the OWUI image; the JSON
#     below is the whole wiring.
#   - `url` is the FULL MCP endpoint: connect_mcp_server passes it straight to
#     the streamable-http client (the `path` field is only used by
#     openapi-type connections).
#   - access_grants: wildcard user grant = usable by every OWUI user. No grant
#     entry => admin-only in has_connection_access (see commit 7e4453a).
#   - Single line: docker env_file cannot parse multi-line values.
set -euo pipefail
cd "$(dirname "$0")/.."

DATA_DIR="services/agenticui"
KEY_FILE="${DATA_DIR}/.webui_secret_key"
OUT_FILE="${DATA_DIR}/generated.env"

# Env wins (generate_config.sh sources .env first); fall back to sourcing .env.
if [ -z "${USER_GOOGLE_EMAIL:-}" ] && [ -f .env ]; then
    set -a; . ./.env; set +a
fi

# 44-char urlsafe base64 = a valid Fernet key, used as-is by Open WebUI's
# derivation (len == 44 skips the sha256 path). Always ensured — the
# container needs it regardless of whether MCP is configured.
if [ ! -s "$KEY_FILE" ]; then
    echo "  • no .webui_secret_key found — generating one (container adopts it at next boot)"
    mkdir -p "$DATA_DIR"
    head -c 32 /dev/urandom | base64 | tr '+/' '-_' > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
fi

if [ -z "${USER_GOOGLE_EMAIL:-}" ]; then
    echo "  • USER_GOOGLE_EMAIL not set — no MCP connection"
    printf '# No MCP connections: USER_GOOGLE_EMAIL not configured\n' > "$OUT_FILE"
    exit 0
fi

printf "TOOL_SERVER_CONNECTIONS='%s'\n" '[{"url":"http://google-workspace-mcp:8000/mcp","type":"mcp","auth_type":"none","config":{"enable":true,"access_grants":[{"principal_type":"user","principal_id":"*","permission":"read"}]},"info":{"id":"google-workspace","name":"Google Workspace","description":"Gmail, Calendar, Docs, Sheets, Drive via the self-hosted workspace-mcp server"}}]' > "$OUT_FILE"
echo "  ✓ Generated 1 MCP connection (google-workspace) → $OUT_FILE"
