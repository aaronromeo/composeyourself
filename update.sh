#!/bin/bash
# Update Compose Yourself services
# Usage: ./update.sh <host>
#   host: "rocketman" or "sweetpaintedlady"
#
# Examples:
#   ./update.sh rocketman         # Update rocketman (Raspberry Pi)
#   ./update.sh sweetpaintedlady  # Update sweetpaintedlady (DigitalOcean)

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validate host argument
if [ $# -ne 1 ]; then
    echo -e "${RED}❌ Error: Host argument required${NC}"
    echo ""
    echo "Usage: ./update.sh <host>"
    echo ""
    echo "Available hosts:"
    echo "  rocketman         - Raspberry Pi (yt-dlp, announcements, immich)"
    echo "  sweetpaintedlady  - DigitalOcean VPS (Open WebUI, Caddy, Authelia)"
    exit 1
fi

HOST="$1"

# Validate host value
case "$HOST" in
    rocketman|sweetpaintedlady)
        echo -e "${GREEN}🔄 Updating $HOST...${NC}"
        ;;
    *)
        echo -e "${RED}❌ Error: Unknown host '$HOST'${NC}"
        echo ""
        echo "Available hosts:"
        echo "  rocketman         - Raspberry Pi"
        echo "  sweetpaintedlady  - DigitalOcean VPS"
        exit 1
        ;;
esac

# Set compose files based on host
if [ "$HOST" = "rocketman" ]; then
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.rocketman.yml"
elif [ "$HOST" = "sweetpaintedlady" ]; then
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.sweetpaintedlady.yml"
fi

# Pull latest changes
echo -e "${YELLOW}🔄 Pulling latest changes...${NC}"
git pull

# Update submodules
echo -e "${YELLOW}🔄 Updating submodules...${NC}"
git submodule update --init --recursive

# Regenerate configuration files (in case templates changed)
echo -e "${YELLOW}⚙️ Regenerating configuration files...${NC}"
chmod +x generate_config.sh
./generate_config.sh

# Rebuild and restart
echo -e "${YELLOW}🏗️ Rebuilding and restarting services...${NC}"
docker compose $COMPOSE_FILES down

# Build locally since services use local Dockerfiles
# (skip compose pull since images aren't prebuilt)
docker compose $COMPOSE_FILES build --no-cache
docker compose $COMPOSE_FILES up -d

echo ""
echo -e "${GREEN}✅ Update complete for $HOST!${NC}"
docker compose $COMPOSE_FILES ps

echo ""
echo "Useful commands:"
echo "  View logs:    docker compose $COMPOSE_FILES logs -f"
echo "  Check status: docker compose $COMPOSE_FILES ps"
