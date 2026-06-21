#!/bin/bash
# Seed OpenWebUI model presets from services/agenticui-config/models.json
#
# Called by deploy.sh and update.sh after `docker compose up -d`.
# Uses POST /api/v1/models/import which upserts by model id — fully idempotent.
#
# Prerequisites:
#   - OPENWEBUI_API_KEY must be set in .env (sk-... admin API key)
#   - ENABLE_API_KEYS=true must be set on the openwebui service (it is, in the
#     compose file) so the API key auth path is active
#
# Bootstrap (one-time, before first use):
#   1. Deploy once (OPENWEBUI_API_KEY can be empty — this script will skip gracefully)
#   2. Log in via Authelia as an openwebui-admin user
#   3. Settings > Account > API Keys > create key (sk-...)
#   4. Add it to .env as OPENWEBUI_API_KEY=sk-...
#   5. Subsequent deploys will auto-seed presets
#
# Network: OWUI has no published host port (expose: 8080 only, on cys-service).
# This script runs a one-shot curl container inside the cys-service network,
# addressing OWUI at http://openwebui:8080. No host port exposure needed.
#
# Usage: ./scripts/seed-openwebui.sh [host]
#   host: "sweetpaintedlady" (default) or any value — exits early for non-SPL hosts

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOST="${1:-sweetpaintedlady}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Only meaningful for sweetpaintedlady (the host that runs openwebui)
if [ "$HOST" != "sweetpaintedlady" ]; then
    echo -e "${YELLOW}  ⏭ seed-openwebui.sh: skipping for host '$HOST' (not sweetpaintedlady)${NC}"
    exit 0
fi

# Load .env
if [ -f "$REPO_ROOT/.env" ]; then
    set -a
    source "$REPO_ROOT/.env"
    set +a
fi

# Skip gracefully if API key not yet configured
if [ -z "${OPENWEBUI_API_KEY}" ]; then
    echo -e "${YELLOW}  ⚠ OPENWEBUI_API_KEY is not set in .env — skipping preset seeding.${NC}"
    echo -e "${YELLOW}    See .env.example for one-time bootstrap instructions.${NC}"
    exit 0
fi

MODELS_JSON="$REPO_ROOT/services/agenticui-config/models.json"
if [ ! -f "$MODELS_JSON" ]; then
    echo -e "${RED}  ✗ models.json not found at $MODELS_JSON${NC}"
    exit 1
fi

COMPOSE_FILES="-f docker-compose.yml -f docker-compose.sweetpaintedlady.yml"
OWUI_URL="http://openwebui:8080"

# ── Readiness poll ──────────────────────────────────────────────────────────
# Poll GET /api/version inside the network until 200 or timeout (60s).
echo -e "${YELLOW}  Waiting for OpenWebUI to be ready...${NC}"

READY=0
for i in $(seq 1 12); do
    STATUS=$(docker compose $COMPOSE_FILES run --rm --no-deps \
        --entrypoint "" \
        -e OWUI_URL="$OWUI_URL" \
        openwebui \
        sh -c 'curl -s -o /dev/null -w "%{http_code}" "$OWUI_URL/api/version"' \
        2>/dev/null || echo "000")

    if [ "$STATUS" = "200" ]; then
        READY=1
        break
    fi
    echo -e "${YELLOW}    ... not ready yet (HTTP $STATUS), retrying in 5s (attempt $i/12)${NC}"
    sleep 5
done

if [ "$READY" != "1" ]; then
    echo -e "${RED}  ✗ OpenWebUI did not become ready within 60s — skipping preset seeding.${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ OpenWebUI is ready${NC}"

# ── Import models ───────────────────────────────────────────────────────────
echo -e "${YELLOW}  Importing model presets from agenticui-config/models.json...${NC}"

# Run curl inside the openwebui container (already on cys-service network)
# so it can reach http://openwebui:8080 without a published host port.
RESPONSE=$(docker compose $COMPOSE_FILES run --rm --no-deps \
    --entrypoint "" \
    -e OWUI_URL="$OWUI_URL" \
    -e OPENWEBUI_API_KEY="$OPENWEBUI_API_KEY" \
    -v "$MODELS_JSON:/tmp/models.json:ro" \
    openwebui \
    sh -c 'curl -s -w "\n%{http_code}" \
        -X POST "$OWUI_URL/api/v1/models/import" \
        -H "Authorization: Bearer $OPENWEBUI_API_KEY" \
        -H "Content-Type: application/json" \
        -d @/tmp/models.json' \
    2>/dev/null)

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

if [ "$HTTP_STATUS" = "200" ] && [ "$HTTP_BODY" = "true" ]; then
    echo -e "${GREEN}  ✓ Model presets seeded successfully${NC}"
else
    echo -e "${RED}  ✗ Import failed (HTTP $HTTP_STATUS)${NC}"
    echo -e "${RED}    Response: $HTTP_BODY${NC}"
    exit 1
fi
