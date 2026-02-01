#!/bin/bash
# Update Compose Yourself services from GitHub

set -e

echo "🔄 Pulling latest changes..."
git pull

echo "🔄 Updating submodules..."
git submodule update --init --recursive

echo "🏗️ Rebuilding and restarting services..."
docker compose down

# Build locally since services use local Dockerfiles
# (skip compose pull since images aren't prebuilt)
docker compose build --no-cache
docker compose up -d

echo "✅ Update complete."
docker compose ps
