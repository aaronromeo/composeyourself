# ComposeYourself

Multi-host Docker Compose stack with MFA-protected services and secure inter-host communication via Tailscale.

## Overview

ComposeYourself is a multi-service Docker stack deployed across two hosts:

- **rocketman** (Raspberry Pi) - Media services: yt-dlp, Discord announcements, Immich photo management
- **sweetpaintedlady** (DigitalOcean VPS) - AI services: Open WebUI with Authelia MFA and Caddy reverse proxy

Both hosts are connected via Tailscale for secure communication.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  sweetpaintedlady.overachieverlabs.com (DigitalOcean)      │
│  ────────────────────────────────────────────────────────   │
│                                                             │
│  Internet ──► Caddy:443 ──► Authelia MFA ──► Open WebUI    │
│       │                                                     │
│       └── Auto HTTPS (Let's Encrypt)                        │
│                                                             │
│  Tailscale ◄────────────────────────────────────────────►   │
│       │                                                     │
└───────┼─────────────────────────────────────────────────────┘
        │
        │ Tailscale mesh network
        │
┌───────┼─────────────────────────────────────────────────────┐
│       │                                                     │
│       ▼                                                     │
│  rocketman (Raspberry Pi)                                  │
│  ────────────────────────────────────────────────────────   │
│                                                             │
│  Services: yt-dlp, announcements, immich (+ redis, db)     │
│  No public exposure (Tailscale-only access)                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
composeyourself/
├── docker-compose.yml                    # Base services (tailscale)
├── docker-compose.rocketman.yml          # Rocketman-specific services
├── docker-compose.sweetpaintedlady.yml   # Sweetpaintedlady-specific services
├── deploy.sh                             # Deployment script (requires host arg)
├── update.sh                             # Update script (requires host arg)
├── composeyourself-rocketman.service     # Systemd service for rocketman
├── composeyourself-sweetpaintedlady.service  # Systemd service for DO
├── services/
│   ├── announcements/                    # Discord webhook service
│   ├── yt-dlp/                           # Video downloader
│   ├── agenticui/                        # Open WebUI data (persistent)
│   ├── caddy/                            # Reverse proxy config
│   └── authelia/                         # MFA authentication config
└── .env.example                          # Environment variables template
```

## Quick Start

### Prerequisites

1. **Both hosts require:**
   - Docker and Docker Compose installed
   - Tailscale auth key (get from [login.tailscale.com](https://login.tailscale.com/admin/settings/keys))

2. **Rocketman (Raspberry Pi):**
   - External storage mounted at `/mnt/storage`
   - dockerops user created

3. **Sweetpaintedlady (DigitalOcean):**
   - Domain `sweetpaintedlady.overachieverlabs.com` with DNS A record
   - Ports 80 and 443 open in firewall

### Clone Repository

```bash
# Clone with submodules
git clone --recurse-submodules git@github.com:aaronromeo/composeyourself.git

# Or initialize after cloning
git submodule update --init --recursive
```

### Environment Configuration

Copy `.env.example` to `.env` and configure:

**Rocketman specific:**
```bash
TAILSCALE_HOSTNAME=rocketman
TS_AUTHKEY=tskey-auth-xxxxxxxxxxxx
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
DB_PASSWORD=your-secure-password
```

**Sweetpaintedlady specific:**
```bash
TAILSCALE_HOSTNAME=sweetpaintedlady
TS_AUTHKEY=tskey-auth-xxxxxxxxxxxx
DOMAIN=sweetpaintedlady.overachieverlabs.com
OPENROUTER_API_KEY=sk-or-v1-xxxxxxxx
AUTHELIA_JWT_SECRET=$(openssl rand -hex 32)
AUTHELIA_SESSION_SECRET=$(openssl rand -hex 32)
AUTHELIA_STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 32)
AUTHELIA_SMTP_HOST=smtp.fastmail.com
AUTHELIA_SMTP_USERNAME=your-email@fastmail.com
AUTHELIA_SMTP_PASSWORD=your-app-password
```

## Deployment

### Rocketman (Raspberry Pi)

1. **Create dockerops user:**
```bash
sudo useradd --system --create-home --home-dir /opt/docker --shell /usr/sbin/nologin dockerops || true
sudo mkdir -p /opt/docker
sudo chown -R dockerops:dockerops /opt/docker
sudo usermod -aG docker dockerops
```

2. **Clone repository:**
```bash
sudo -u dockerops git clone git@github.com:aaronromeo/composeyourself.git /opt/docker/composeyourself
sudo -u dockerops git -C /opt/docker/composeyourself submodule update --init --recursive
```

3. **Configure environment:**
```bash
sudo -u dockerops cp /opt/docker/composeyourself/.env.example /opt/docker/composeyourself/.env
sudo -u dockerops nano /opt/docker/composeyourself/.env
# Set TAILSCALE_HOSTNAME=rocketman and other variables
```

4. **Setup storage permissions:**
```bash
sudo groupadd -f dockershare
sudo usermod -aG dockershare dockerops
sudo mkdir -p /mnt/storage/media/audio /mnt/storage/media/.logs /mnt/storage/media/photos/library
sudo chgrp -R dockershare /mnt/storage
sudo chmod -R g+rwX /mnt/storage
sudo find /mnt/storage -type d -exec chmod g+s {} \;
```

5. **Install systemd service:**
```bash
sudo cp /opt/docker/composeyourself/composeyourself-rocketman.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable composeyourself-rocketman.service
```

6. **Deploy:**
```bash
cd /opt/docker/composeyourself
sudo -u dockerops ./deploy.sh rocketman
```

### Sweetpaintedlady (DigitalOcean)

1. **Create dockerops user:**
```bash
sudo useradd --system --create-home --home-dir /opt/docker --shell /usr/sbin/nologin dockerops || true
sudo mkdir -p /opt/docker
sudo chown -R dockerops:dockerops /opt/docker
sudo usermod -aG docker dockerops
```

2. **Clone repository:**
```bash
sudo -u dockerops git clone git@github.com:aaronromeo/composeyourself.git /opt/docker/composeyourself
```

3. **Configure environment:**
```bash
sudo -u dockerops cp /opt/docker/composeyourself/.env.example /opt/docker/composeyourself/.env
sudo -u dockerops nano /opt/docker/composeyourself/.env
# Set all sweetpaintedlady-specific variables
```

4. **Setup Authelia users:**
```bash
# Generate password hash for your user
# After first deployment, exec into authelia container:
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml exec authelia bash
authelia crypto hash generate argon2 --password 'YourSecurePassword123!'

# Copy the hash and update services/authelia/users_database.yml
```

5. **Install systemd service:**
```bash
sudo cp /opt/docker/composeyourself/composeyourself-sweetpaintedlady.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable composeyourself-sweetpaintedlady.service
```

6. **Deploy:**
```bash
cd /opt/docker/composeyourself
sudo -u dockerops ./deploy.sh sweetpaintedlady
```

7. **Setup DNS:**
   - Create A record: `sweetpaintedlady.overachieverlabs.com` → Your DO droplet IP
   - Wait for DNS propagation

## Service Management

### Rocketman

```bash
# Deploy or update
cd /opt/docker/composeyourself
./deploy.sh rocketman
./update.sh rocketman

# Check status
docker compose -f docker-compose.yml -f docker-compose.rocketman.yml ps
docker compose -f docker-compose.yml -f docker-compose.rocketman.yml logs -f

# Restart service
docker compose -f docker-compose.yml -f docker-compose.rocketman.yml restart <service>

# View systemd logs
sudo journalctl -u composeyourself-rocketman.service -f
```

### Sweetpaintedlady

```bash
# Deploy or update
cd /opt/docker/composeyourself
./deploy.sh sweetpaintedlady
./update.sh sweetpaintedlady

# Check status
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml ps
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml logs -f

# Restart service
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml restart <service>

# View systemd logs
sudo journalctl -u composeyourself-sweetpaintedlady.service -f
```

## Accessing Services

### Rocketman (via Tailscale)

All services are accessible only via Tailscale network:

- **yt-dlp**: http://rocketman:8080
- **announcements**: http://rocketman:8091
- **immich**: http://rocketman:2283

### Sweetpaintedlady (Public with MFA)

- **Open WebUI**: https://sweetpaintedlady.overachieverlabs.com
  - Requires Authelia authentication (username + password + 2FA)
- **Authelia Portal**: https://auth.sweetpaintedlady.overachieverlabs.com (optional)

## Authelia User Management

### Adding a New User

1. Generate password hash:
```bash
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml exec authelia bash
authelia crypto hash generate argon2 --password 'NewUserPassword123!'
```

2. Edit `services/authelia/users_database.yml`:
```yaml
newuser:
  displayname: "New User"
  password: "$argon2id$v=19$m=65536,t=3,p=4$..."  # paste hash here
  email: newuser@example.com
  groups:
    - users
```

3. Restart Authelia:
```bash
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml restart authelia
```

### Resetting a Password

Users can request password reset via the Authelia login page. An email with reset link will be sent via configured SMTP.

## Inter-Host Communication

Both hosts communicate via Tailscale:

```bash
# From sweetpaintedlady, test connection to rocketman
ping rocketman

# Access rocketman services from sweetpaintedlady
curl http://rocketman:8091/health
```

## Troubleshooting

### Rocketman

**Service won't start:**
```bash
# Check logs
docker compose -f docker-compose.yml -f docker-compose.rocketman.yml logs <service>

# Verify storage permissions
ls -la /mnt/storage/media/
sudo chown -R dockerops:dockershare /mnt/storage/media

# Check disk space
df -h /mnt/storage
```

**Tailscale not connecting:**
```bash
# Check tailscale status
sudo tailscale status

# Reauthenticate if needed
sudo tailscale up --force-reauth
```

### Sweetpaintedlady

**HTTPS not working:**
```bash
# Check DNS resolution
dig sweetpaintedlady.overachieverlabs.com

# Verify Caddy logs
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml logs caddy

# Check if ports 80/443 are open
sudo ufw status
```

**Authelia authentication fails:**
```bash
# Check Authelia logs
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml logs authelia

# Verify users_database.yml syntax
# Ensure password hashes are valid Argon2 format
```

**Cannot access Open WebUI after authentication:**
```bash
# Check all services are running
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml ps

# Verify Open WebUI is healthy
docker compose -f docker-compose.yml -f docker-compose.sweetpaintedlady.yml exec openwebui curl http://localhost:8080/api/version
```

### General

**Permission denied with dockerops user:**
```bash
# Add dockerops to docker group
sudo usermod -aG docker dockerops
# Log out and back in for changes to take effect
```

**Git submodule issues:**
```bash
# Reinitialize submodules
git submodule update --init --recursive --force
```

## Security Notes

- **Rocketman**: No public exposure - all services only accessible via Tailscale
- **Sweetpaintedlady**: Public HTTPS with mandatory MFA via Authelia
- **Secrets**: Never commit `.env` file to git - use `.env.example` as template
- **Passwords**: Use strong passwords and enable 2FA for all Authelia users
- **Updates**: Keep Docker images updated with `./update.sh <host>`

## Future Enhancements

- [ ] Automated backups from sweetpaintedlady to rocketman
- [ ] BackBlaze B2 offsite backup integration
- [ ] Monitoring/alerting with Prometheus/Grafana
- [ ] Centralized logging

## Support

For issues or questions:
1. Check the logs: `docker compose -f docker-compose.yml -f docker-compose.<host>.yml logs -f`
2. Verify container status: `docker compose ps`
3. Check Tailscale connectivity: `tailscale status`
4. Review [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for detailed architecture

## License

MIT License - See LICENSE file for details
