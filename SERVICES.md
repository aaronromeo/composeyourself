# Multi-Service Architecture for Raspberry Pi

## Overview

This project is designed to host multiple Docker services on your Raspberry Pi in an organized, scalable way. Each service is isolated in its own directory but managed through a single docker-compose.yml file.

## Current Services

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
