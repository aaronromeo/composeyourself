#!/bin/bash
# Deploy Compose Yourself services
# Usage: ./deploy.sh <host>
#   host: "rocketman" or "sweetpaintedlady"
#
# Examples:
#   ./deploy.sh rocketman         # Deploy to rocketman (Raspberry Pi)
#   ./deploy.sh sweetpaintedlady  # Deploy to sweetpaintedlady (DigitalOcean)

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
    echo "Usage: ./deploy.sh <host>"
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
        echo -e "${GREEN}🚀 Deploying to $HOST...${NC}"
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
    echo -e "${YELLOW}📦 Services: yt-dlp, announcements, immich${NC}"
elif [ "$HOST" = "sweetpaintedlady" ]; then
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.sweetpaintedlady.yml"
    echo -e "${YELLOW}📦 Services: Open WebUI, Caddy, Authelia${NC}"
fi

# Update submodules
echo -e "${YELLOW}🔄 Updating submodules...${NC}"
git submodule update --init --recursive

# Host-specific setup
if [ "$HOST" = "rocketman" ]; then
    echo -e "${YELLOW}🏗️ Setting up directories for rocketman...${NC}"
    sudo mkdir -p /mnt/storage/media/audio /mnt/storage/media/.logs /mnt/storage/media/photos/library
    sudo chown -R pi:pi /mnt/storage/media
    [ -e ./services/immich/library ] || ln -s /mnt/storage/media/photos/library ./services/immich/library
fi

# Build and deploy
echo -e "${YELLOW}🏗️ Building and starting services...${NC}"
docker compose $COMPOSE_FILES down
docker compose $COMPOSE_FILES build --no-cache
docker compose $COMPOSE_FILES up -d

# Check deployment status
echo -e "${GREEN}✅ Checking deployment status...${NC}"
docker compose $COMPOSE_FILES ps

echo ""
echo -e "${GREEN}✅ Deployment to $HOST complete!${NC}"
echo ""
echo "Useful commands:"
echo "  View logs:    docker compose $COMPOSE_FILES logs -f"
echo "  Check status: docker compose $COMPOSE_FILES ps"
echo "  Stop:         docker compose $COMPOSE_FILES down"

if [ "$HOST" = "sweetpaintedlady" ]; then
    echo ""
    echo -e "${YELLOW}🌐 Access Open WebUI at: https://sweetpaintedlady.overachieverlabs.com${NC}"
    echo -e "${YELLOW}🔐 You'll need to authenticate via Authelia first${NC}"
fi
