# Multi-Service Architecture for Raspberry Pi

## Overview

This project is designed to host multiple Docker services on your Raspberry Pi in an organized, scalable way. Each service is isolated in its own directory but managed through a single docker-compose.yml file.

## Current Services

### Open WebUI (sweetpaintedlady)
- **Location**: `services/agenticui/` (runtime data), `services/agenticui-config/` (as-code config)
- **Access**: `https://${SUBDOMAIN}.${DOMAIN}` (via Caddy + Authelia)
- **Purpose**: AI chat interface backed by OpenRouter

#### Default model + presets (as code)

Settings are version-controlled and re-applied on every deploy — no clicking in the admin UI.

**Default model** (`services/agenticui-config/config.json`):
- New chats default to `anthropic/claude-sonnet-4.6`
- `generate_config.sh` copies this file into `services/agenticui/` before `docker compose up`
- OWUI imports it on boot (renames to `old_config.json`), re-asserting the default each deploy

**Model presets** (`services/agenticui-config/models.json`):

| Preset | Base model | Purpose |
|---|---|---|
| Cheap | `qwen/qwen3-coder` | Routine coding, refactors, grunt work |
| Deep | `anthropic/claude-opus-4.8` | Architecture, hard debugging, high-stakes decisions |

Seeded via `scripts/seed-openwebui.sh` after each deploy using `POST /api/v1/models/import`
(upserts by id — idempotent, safe to re-run).

#### Bootstrap — one-time API key setup (required for preset seeding)

Preset seeding requires an admin API key. The first deploy skips seeding gracefully
if the key is not yet set.

1. Deploy once (leave `OPENWEBUI_API_KEY` empty in `.env` — seed step will warn and skip).
2. Log in to OpenWebUI via Authelia as an `openwebui-admin` user.
3. Go to **Settings → Account → API Keys** → create a new key (`sk-...`).
4. Add it to `.env`:
   ```
   OPENWEBUI_API_KEY=sk-...
   ```
5. Re-deploy. All subsequent deploys will auto-seed the presets.

#### Changing defaults or presets

- **Default model**: edit `services/agenticui-config/config.json` → change `ui.default_models`.
- **Presets (system prompt, base model, params)**: edit `services/agenticui-config/models.json`.
- Deploy → changes take effect on the next boot/import.

#### webui.db persistence check

On a running `sweetpaintedlady` host, verify persistence:
```bash
ls -la services/agenticui/   # should show webui.db, uploads/, cache/
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml \
    exec openwebui ls -la /app/backend/data
```
If `webui.db` is in the container but not on the host, the bind mount is not
capturing data. Check that `./services/agenticui` resolves correctly and that
the container user (root) can write to it.

---

### yt-dlp Web Interface
- **Location**: `services/yt-dlp/`
- **Port**: 8080
- **Purpose**: Download videos/audio from YouTube and other sites
- **Features**: Web UI, queue management, audio extraction, progress monitoring

## Planned Services (Examples)

### Media Server Options
- **Jellyfin**: `services/jellyfin/` - Open-source media server
- **Plex**: `services/plex/` - Popular media server
- **Emby**: `services/emby/` - Alternative media server

### Download Management
- **qBittorrent**: `services/qbittorrent/` - Torrent client with web UI
- **Transmission**: `services/transmission/` - Lightweight torrent client
- **SABnzbd**: `services/sabnzbd/` - Usenet downloader

### File Management
- **Nextcloud**: `services/nextcloud/` - Self-hosted cloud storage
- **FileBrowser**: `services/filebrowser/` - Web-based file manager
- **Syncthing**: `services/syncthing/` - File synchronization

### Monitoring & Management
- **Portainer**: `services/portainer/` - Docker container management
- **Grafana**: `services/grafana/` - Monitoring dashboards
- **Prometheus**: `services/prometheus/` - Metrics collection

## Architecture Benefits

### Service Isolation
- Each service has its own directory
- Independent Dockerfiles and configurations
- Separate deployment scripts available
- Services can be updated independently

### Shared Infrastructure
- Single docker-compose.yml for orchestration
- Shared network (`pi-services`) for inter-service communication
- Common volume mounts for shared data
- Centralized logging and monitoring

### Easy Management
- Deploy all services: `./deploy.sh`
- Deploy specific service: `./deploy-[service].sh`
- Standard Docker Compose commands work
- Service-specific commands available

## Directory Structure

```
/home/pi/workspace/composeyourself/
├── docker-compose.yml              # Multi-service orchestration
├── deploy.sh                       # Deploy all services
├── deploy-yt-dlp.sh               # Deploy yt-dlp only
├── services/
│   ├── yt-dlp/                    # Current: yt-dlp web interface
│   │   ├── Dockerfile
│   │   ├── app.py
│   │   ├── requirements.txt
│   │   └── templates/
│   ├── jellyfin/                  # Future: Media server
│   │   ├── docker-compose.override.yml
│   │   └── config/
│   ├── qbittorrent/              # Future: Torrent client
│   │   ├── Dockerfile
│   │   └── config/
│   └── [other services...]
├── shared/                        # Shared configurations
│   ├── nginx/                     # Reverse proxy configs
│   └── ssl/                       # SSL certificates
└── README.md
```

## Port Allocation

To avoid conflicts, here's the planned port allocation:

| Service | Port | Purpose |
|---------|------|---------|
| yt-dlp | 8080 | Video/audio downloader |
| Jellyfin | 8096 | Media server |
| qBittorrent | 8081 | Torrent web UI |
| Portainer | 9000 | Docker management |
| FileBrowser | 8082 | File management |
| Grafana | 3000 | Monitoring |
| Nextcloud | 8083 | Cloud storage |

## Service Communication

Services communicate through the `pi-services` Docker network:
- Internal DNS resolution (service names)
- Isolated from host network
- Secure inter-service communication
- Easy service discovery

## Adding New Services

1. **Create service directory**: `mkdir services/new-service`
2. **Add service files**: Dockerfile, configs, etc.
3. **Update docker-compose.yml**: Add service definition
4. **Create deployment script**: Copy and modify existing script
5. **Update documentation**: Add to this file and README

## Best Practices

### Resource Management
- Set memory limits for each service
- Use health checks for monitoring
- Configure restart policies
- Monitor disk usage

### Security
- Use non-root users in containers
- Limit exposed ports
- Use secrets for sensitive data
- Regular security updates

### Backup Strategy
- Configuration files in version control
- Data volumes backed up regularly
- Easy restore procedures
- Disaster recovery plan

## Cloudflare Tunnel Integration

All services can be exposed through Cloudflare tunnels:

```yaml
# /etc/cloudflared/config.yml
ingress:
  - hostname: ytdlp.romeothedarkhorse.ca
    service: http://localhost:8080
  - hostname: jellyfin.romeothedarkhorse.ca
    service: http://localhost:8096
  - hostname: files.romeothedarkhorse.ca
    service: http://localhost:8082
  - hostname: ssh.romeothedarkhorse.ca
    service: ssh://localhost:22
  - service: http_status:404
```

This allows secure external access to all services through your domain.
