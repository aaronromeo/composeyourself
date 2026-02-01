#!/bin/bash
# Deploy Compose Yourself services to Raspberry Pi

set -e

echo "🔄 Updating submodules..."
git submodule update --init --recursive

echo "🏗️ Building and starting services on Pi..."
sudo mkdir -p /mnt/storage/media/audio /mnt/storage/media/.logs /mnt/storage/media/photos/library && \
sudo chown -R pi:pi /mnt/storage/media && \
[ -e ./services/immich/library ] || ln -s /mnt/storage/media/photos/library ./services/immich/library && \
docker compose down && \
docker compose build --no-cache && \
docker compose up -d

echo "✅ Checking deployment status..."
docker compose ps && docker compose logs --tail=20
