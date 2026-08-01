#!/bin/bash
# Restart Compose Yourself services
# Usage: ./restart.sh <host>
#   host: "rocketman" or "sweetpaintedlady"
#
# Takes the stack down and brings it back up without touching git, config
# generation, or image builds. Safe to run any time, including when the repo
# is already up to date (unlike update.sh, which early-exits).
#
# Examples:
#   ./restart.sh rocketman          # Restart rocketman stack (incl. SigNoz)
#   ./restart.sh sweetpaintedlady   # Restart sweetpaintedlady stack

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Lock file shared with update.sh so a manual restart can't race a scheduled
# update. Skipped (via CYS_SKIP_LOCK=1) when invoked from update.sh, which
# already holds the lock for its whole run.
LOCKFILE="/tmp/composeyourself-update.lock"
exec 200>"$LOCKFILE"
if [ "$CYS_SKIP_LOCK" != "1" ]; then
    flock -n 200 || { echo -e "${RED}❌ Another update or restart is already running — exiting.${NC}"; exit 1; }
fi

# Validate host argument
if [ $# -ne 1 ]; then
    echo -e "${RED}❌ Error: Host argument required${NC}"
    echo ""
    echo "Usage: ./restart.sh <host>"
    echo "  rocketman        - Raspberry Pi (yt-dlp, announcements, immich, signoz)"
    echo "  sweetpaintedlady - DigitalOcean VPS (Open WebUI, Caddy, Authelia)"
    exit 1
fi

HOST="$1"

# Validate host value
case "$HOST" in
    rocketman|sweetpaintedlady)
        echo -e "${GREEN}🔄 Restarting $HOST services...${NC}"
        ;;
    *)
        echo -e "${RED}❌ Error: Unknown host '$HOST'${NC}"
        echo ""
        echo "Available hosts:"
        echo "  rocketman        - Raspberry Pi"
        echo "  sweetpaintedlady - DigitalOcean VPS"
        exit 1
        ;;
esac

# Set compose files based on host
if [ "$HOST" = "rocketman" ]; then
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.rocketman.yml -f services/signoz/docker-compose.signoz.yml"
elif [ "$HOST" = "sweetpaintedlady" ]; then
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.sweetpaintedlady.yml"
fi

# Validate compose config before taking anything down
echo -e "${YELLOW}⚙️ Validating compose configuration...${NC}"
docker compose $COMPOSE_FILES config > /dev/null || { echo -e "${RED}❌ Config validation failed${NC}"; exit 1; }

# Take the stack down and bring it back up. up -d re-uses existing images
# (no pull/build — this is a restart, not an update).
echo -e "${YELLOW}⏬ Taking services down...${NC}"
docker compose $COMPOSE_FILES down
echo -e "${YELLOW}⏫ Bringing services back up...${NC}"
docker compose $COMPOSE_FILES up -d --remove-orphans

# Seed OpenWebUI model presets (idempotent; no-op on rocketman / without API key)
echo -e "${YELLOW}🌱 Seeding OpenWebUI presets...${NC}"
chmod +x scripts/seed-openwebui.sh
./scripts/seed-openwebui.sh "$HOST" || echo -e "${YELLOW}⚠️  Preset seeding skipped or failed (non-fatal — see output above)${NC}"

echo ""
echo -e "${GREEN}✅ Restart of $HOST complete!${NC}"
docker compose $COMPOSE_FILES ps
