#!/usr/bin/env bash
# Generates services/agenticui/generated.env (TOOL_SERVER_CONNECTIONS) wiring
# Open WebUI to Google's Workspace MCP servers (Gmail / Calendar / Docs /
# Sheets), read-only scopes.
#
# Called by generate_config.sh on every deploy. No-op (comment-only file) when
# GOOGLE_MCP_CLIENT_ID / GOOGLE_MCP_CLIENT_SECRET are not set — e.g. on hosts
# where scripts/gcp-mcp-setup.sh hasn't been run.
#
# Design:
#   - The openwebui container reads its signing/encryption key from
#     WEBUI_SECRET_KEY_FILE=/app/backend/data/.webui_secret_key (set in
#     docker-compose.sweetpaintedlady.yml; start.sh default would be
#     /app/backend/.webui_secret_key — outside the volume, regenerated on
#     every container recreate, invalidating logins and MCP tokens). This
#     script ensures that file exists so the key persists across deploys.
#   - The Fernet blobs must decrypt inside the running container, so they are
#     encrypted with that same key.
#   - Blobs are built INSIDE the pinned Open WebUI image by calling the same
#     function the Admin UI's "Register Client" uses (live RFC 9728 discovery
#     against Google), so the schema, endpoints and resource parameter always
#     match the deployed version.
set -euo pipefail
cd "$(dirname "$0")/.."

DATA_DIR="services/agenticui"
KEY_FILE="${DATA_DIR}/.webui_secret_key"
OUT_FILE="${DATA_DIR}/generated.env"

# Image pin follows the compose file (single source of truth).
OPENWEBUI_IMAGE=$(grep -m1 -o 'ghcr.io/open-webui/open-webui:[^ "'"'"']*' docker-compose.sweetpaintedlady.yml)
if [ -z "$OPENWEBUI_IMAGE" ]; then
    echo "  ✗ couldn't find the open-webui image pin in docker-compose.sweetpaintedlady.yml" >&2
    exit 1
fi

# Env wins (generate_config.sh sources .env first); fall back to sourcing .env.
if [ -z "${GOOGLE_MCP_CLIENT_ID:-}" ] && [ -f .env ]; then
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

if [ -z "${GOOGLE_MCP_CLIENT_ID:-}" ] || [ -z "${GOOGLE_MCP_CLIENT_SECRET:-}" ] \
   || [ -z "${DOMAIN:-}" ] || [ -z "${SUBDOMAIN:-}" ]; then
    echo "  • GOOGLE_MCP_* / DOMAIN / SUBDOMAIN not all set — no MCP connections"
    printf '# No MCP connections: GOOGLE_MCP_* not configured\n' > "$OUT_FILE"
    exit 0
fi

WEBUI_URL="https://${SUBDOMAIN}.${DOMAIN}"
WEBUI_URL="${WEBUI_URL%/}"

if ! JSON=$(docker run --rm -i --entrypoint python3 \
    -e ENABLE_PERSISTENT_CONFIG=False \
    -e WEBUI_URL="$WEBUI_URL" \
    -e WEBUI_SECRET_KEY="$(cat "$KEY_FILE")" \
    -e CLIENT_ID="$GOOGLE_MCP_CLIENT_ID" \
    -e CLIENT_SECRET="$GOOGLE_MCP_CLIENT_SECRET" \
    "$OPENWEBUI_IMAGE" - <<'PY'
import asyncio
import json
import os
import sys

sys.path.insert(0, '/app/backend')

CLIENT_ID = os.environ['CLIENT_ID']
CLIENT_SECRET = os.environ['CLIENT_SECRET']

from open_webui.utils.oauth import (
    decrypt_data,
    encrypt_data,
    get_oauth_client_info_with_static_credentials,
)

# service id, display name, MCP endpoint, OAuth scopes.
# ponytail: read-only scopes; add gmail.compose / calendar event write when needed
SERVICES = [
    ('google-gmail', 'Google Gmail', 'https://gmailmcp.googleapis.com/mcp/v1',
     'https://www.googleapis.com/auth/gmail.readonly'),
    ('google-calendar', 'Google Calendar', 'https://calendarmcp.googleapis.com/mcp/v1',
     'https://www.googleapis.com/auth/calendar.calendarlist.readonly '
     'https://www.googleapis.com/auth/calendar.events.freebusy '
     'https://www.googleapis.com/auth/calendar.events.readonly'),
    ('google-docs', 'Google Docs', 'https://docsmcp.googleapis.com/mcp/v1',
     'https://www.googleapis.com/auth/drive.readonly '
     'https://www.googleapis.com/auth/documents.readonly'),
    ('google-sheets', 'Google Sheets', 'https://sheetsmcp.googleapis.com/mcp/v1',
     'https://www.googleapis.com/auth/drive.readonly '
     'https://www.googleapis.com/auth/spreadsheets.readonly'),
]


async def main():
    connections = []
    for service_id, name, url, scope in SERVICES:
        # Same code path as the Admin UI's Register Client with static creds:
        # live RFC 9728 discovery against Google (correct endpoints, resource
        # parameter and metadata), redirected to /oauth/clients/mcp:<id>/callback.
        info = await get_oauth_client_info_with_static_credentials(
            request=None,
            client_id=f'mcp:{service_id}',
            oauth_server_url=url,
            oauth_client_id=CLIENT_ID,
            oauth_client_secret=CLIENT_SECRET,
            oauth_scope=scope,
        )
        blob = encrypt_data(info.model_dump(mode='json'))
        # Sanity: must round-trip through the same decrypt the app will do.
        assert decrypt_data(blob)['client_id'] == CLIENT_ID
        connections.append({
            'url': url,
            'path': '/mcp',
            'type': 'mcp',
            'auth_type': 'oauth_2.1_static',
            'headers': None,
            'key': None,
            # ponytail: no access_grants => admin-only in has_connection_access;
            # wildcard user grant makes the servers usable by every user.
            'config': {
                'enable': True,
                'access_grants': [
                    {'principal_type': 'user', 'principal_id': '*', 'permission': 'read'}
                ],
            },
            'info': {
                'id': service_id,
                'name': name,
                'oauth_client_id': CLIENT_ID,
                'oauth_client_secret': CLIENT_SECRET,
                'oauth_client_info': blob,
            },
        })
    print('<<<MCP_CONNECTIONS_JSON>>>' + json.dumps(connections, separators=(',', ':')))


asyncio.run(main())
PY
); then
    echo "  ✗ MCP connection generation failed" >&2
    rm -f "$OUT_FILE"
    exit 1
fi

# Strip container log noise (config-import runs alembic on an ephemeral
# sqlite); the JSON is the single line after the marker.
JSON="${JSON##*<<<MCP_CONNECTIONS_JSON>>>}"

printf "TOOL_SERVER_CONNECTIONS='%s'\n" "$JSON" > "$OUT_FILE"
echo "  ✓ Generated 4 MCP connections (Gmail/Calendar/Docs/Sheets) → $OUT_FILE"
