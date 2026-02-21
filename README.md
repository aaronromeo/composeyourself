# ComposeYourself

ComposeYourself is a multi-service Docker stack for a Raspberry Pi (or any Linux host) designed for easy expansion with additional services.

## Current Services

See `docker-compose.yml` for the active service list. Services may be added/removed over time.

- `yt-dlp` on `http://<host>:8080`
- `announcements` on `127.0.0.1:8091`
- `immich-server` on `http://<host>:2283`
- `openwebui` on `http://127.0.0.1:3000`

## Project Structure

This repo uses Git submodules for some services. Make sure to initialize them before building or deploying.

```
/home/pi/workspace/composeyourself/
├── docker-compose.yml          # Multi-service orchestration
├── services/
│   ├── agenticui/              # Open WebUI persistent data
│   ├── announcements/         # Service submodule
│   └── yt-dlp/                 # Service submodule
└── [future services...]       # Additional services go here
```

## Service Organization

Each service is organized in its own directory under `services/`:
- **Isolated builds** - Each service has its own Dockerfile
- **Independent deployment** - Services can be deployed/updated separately
- **Shared networking** - All services use the `pi-services` network
- **Centralized orchestration** - Single docker-compose.yml manages all services

## Quick Start

### Submodules
```bash
# Clone with submodules
git clone --recurse-submodules git@github.com:aaronromeo/composeyourself.git

# Or initialize after cloning
git submodule update --init --recursive
```

### Deploy All Services
```bash
# Deploy everything with one command
./deploy.sh
```

### Deploy Specific Service (yt-dlp)
```bash
# Deploy only a specific service
docker compose up -d <service-name>
```

### Manual Deployment
```bash
# Copy files to Pi
scp -r . pi@nikita:/home/pi/workspace/composeyourself

# SSH to Pi and deploy
ssh pi@nikita
cd /home/pi/workspace/composeyourself

# Create directories
sudo mkdir -p /mnt/storage/media/downloads/audio /mnt/storage/media/downloads/.logs
sudo chown -R pi:pi /mnt/storage/media/downloads

# Build and start all services
docker compose build
docker compose up -d

# Or start a specific service
docker compose up -d <service-name>
```

### Pull the latest
```bash
sudo -u dockerops git -C /opt/docker/composeyourself pull
sudo -u dockerops git -C /opt/docker/composeyourself submodule update --init --recursive
./update.sh
```

## Deployment

1. Create a dedicated service account
```bash
sudo useradd --system --create-home --home-dir /opt/docker --shell /usr/sbin/nologin dockerops || true
sudo mkdir -p /opt/docker
sudo chown -R dockerops:dockerops /opt/docker
```

2. Create an SSH key for dockerops
```bash
sudo -u dockerops ssh-keygen -t ed25519 -C "dockerops@rocketman" -f /opt/docker/.ssh/id_ed25519
sudo -u dockerops cat /opt/docker/.ssh/id_ed25519.pub
```

3. Add that key in GitHub → Settings → SSH and GPG keys.

4. Clone using SSH
```bash
sudo -u dockerops git clone git@github.com:aaronromeo/composeyourself.git /opt/docker/composeyourself
sudo -u dockerops git -C /opt/docker/composeyourself submodule update --init --recursive
```

5. Apply the shared-group permissions to the USB mount (so dockerops can write too)
```bash
sudo groupadd -f dockershare
sudo usermod -aG dockershare [non-root-system-user]
sudo usermod -aG dockershare dockerops

sudo mkdir /mnt/storage/logs
sudo chgrp -R dockershare /mnt/storage
sudo chmod -R g+rwX /mnt/storage
sudo find /mnt/storage -type d -exec chmod g+s {} \;

sudo setfacl -R -m g:dockershare:rwx /mnt/storage
sudo setfacl -R -d -m g:dockershare:rwx /mnt/storage
```

6. Install service
```bash
cp /opt/docker/composeyourself/composeyourself.service /etc/systemd/system/composeyourself.service 
```

7. Setup the .env file
```bash
sudo -u dockerops vi /opt/docker/composeyourself/.env
```

7. Enable the daemon file
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now composeyourself.service
```

## Service Management

### All Services
```bash
# Check status of all services
docker compose ps

# View logs for all services
docker compose logs -f

# Stop all services
docker compose down

# Restart all services
docker compose restart

# Update and rebuild all services
docker compose build --no-cache
docker compose up -d
```

### Specific Service
```bash
# Check service status
docker compose ps <service-name>

# View service logs
docker compose logs -f <service-name>

# Restart service only
docker compose restart <service-name>

# Stop service only
docker compose stop <service-name>

# Rebuild and restart service
docker compose build <service-name> --no-cache
docker compose up -d <service-name>
```

## Configuration

Configuration is service-specific. See each service's README or the service directory for details.

### Open WebUI + OpenRouter

Open WebUI is configured in `docker-compose.yml` with:
- Port mapping: `127.0.0.1:3000:8080`
- Persistent data: `./services/agenticui:/app/backend/data`
- OpenRouter base URL: `OPENAI_API_BASE_URL=https://openrouter.ai/api/v1`
- API key mapping: `OPENAI_API_KEY=${OPENROUTER_API_KEY}`

Set this in `.env`:

```bash
OPENROUTER_API_KEY=your_openrouter_api_key_here
```

Then start only Open WebUI:

```bash
docker compose up -d openwebui
```

## Troubleshooting

### Container Won't Start
```bash
# Check logs
docker compose logs yt-dlp-web

# Check disk space
df -h /mnt/storage

# Check permissions
ls -la /mnt/storage/media/downloads
```

### Build Fails
```bash
# Clean build
docker compose down
docker system prune -f
docker compose build --no-cache
```

## File Structure

```
.
├── docker-compose.yml          # Multi-service orchestration
├── deploy.sh                   # Deploy all services
├── update.sh                   # Pull and refresh services
├── services/
│   ├── agenticui/              # Open WebUI persistent data
│   ├── announcements/         # Service submodule
│   └── yt-dlp/                # Service submodule
└── README.md                  # This file
```

## Adding New Services

To add a new service (e.g., Jellyfin, Plex, etc.):

1. **Create service directory**:
   ```bash
   mkdir -p services/new-service
   ```

2. **Add service files**:
   - `Dockerfile` (if custom build needed)
   - Configuration files
   - Any service-specific scripts

3. **Update docker-compose.yml**:
   ```yaml
   services:
     new-service:
       build: ./services/new-service  # or use existing image
       container_name: new-service
       restart: unless-stopped
       ports:
         - "PORT:PORT"
       volumes:
         - ./services/new-service/config:/config
       networks:
         - pi-services
   ```

4. **Create deployment script** (optional):
   ```bash
   cp deploy-yt-dlp.sh deploy-new-service.sh
   # Edit to match new service
   ```

## Support

For issues or questions:
1. Check the logs: `docker compose logs -f`
2. Verify container status: `docker compose ps`
