# Phase 1 — Findings (rocketman inspection)

**Date:** 2026-07-13 (repo analysis: 2026-08-02)
**Status:** Partial — SSH to rocketman unavailable from this machine.
Items marked `[REPO]` are confirmed from committed config. Items marked `[LIVE]`
require on-box inspection before Phase 2 can run.

---

## Blockers (must resolve before Phase 2)

| # | What | Why |
|---|------|-----|
| 1 | `[LIVE]` Actual `UPLOAD_LOCATION` and `DB_DATA_LOCATION` | .env.example shows `./library` / `./postgres` (relative, in compose dir). Spec and yt-dlp config suggest `/mnt/storage` mount. The real `.env` on rocketman has the authoritative paths. |
| 2 | `[LIVE]` USB backup disk — device, UUID, filesystem | Spec assumes USB at `/mnt/backup`, ext4. `lsblk -f` + `df -h` needed. |
| 3 | `[LIVE]` borg and rclone — installed? versions? | Toolchain must be present or installed in Phase 2. |
| 4 | `[LIVE]` B2 credentials — rclone remote configured? | rclone remote named `b2:` or similar. `rclone listremotes`. |
| 5 | `[LIVE]` Borg passphrase — must be generated and stored off-machine | Human step, blocking gate in plan.md. |

---

## Step 1 — Inspection Results

### Immich version and how it runs

- **[REPO] CONFIRMED:** Immich runs via Docker Compose.
  Compose file: `docker-compose.rocketman.yml` (lines 113-202).
  Working directory: `/opt/docker/composeyourself` (per systemd unit).
  Images:
  - `immich_server`: `ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}`
  - `immich_machine_learning`: `ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-release}`
  - `immich_redis`: `docker.io/valkey/valkey:8@sha256:81db...` (Valkey, drop-in Redis replacement)
  - `immich_postgres`: `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf6...`
- **[REPO] CONFIRMED:** `IMMICH_VERSION=v2.7.5` in `.env.example`.
- `[LIVE]` Actual running version: `docker inspect immich_server | jq -r '.[0].Config.Image'`

### Container names

- **[REPO] CONFIRMED:**
  | Container | Compose Service | Name |
  |-----------|----------------|------|
  | immich_server | `immich-server` | `immich_server` |
  | immich_machine_learning | `immich-machine-learning` | `immich_machine_learning` |
  | immich_redis | `redis` | `immich_redis` |
  | immich_postgres | `database` | `immich_postgres` |
- **[REPO] CONFIRMED:** Spec assumption `immich_postgres` matches compose config.

### UPLOAD_LOCATION

- **[REPO]** `.env.example` shows `UPLOAD_LOCATION=./library` (relative to `/opt/docker/composeyourself`).
- **[REPO]** `docker-compose.rocketman.yml` L119: `${UPLOAD_LOCATION}:/data`.
- **[REPO]** yt-dlp uses `/mnt/storage/media/downloads`, suggesting `/mnt/storage` exists as a mount point.
- `[LIVE]` Actual `UPLOAD_LOCATION` value from `.env` on rocketman.
- `[LIVE]` Expected subdirs: `library/`, `upload/`, `profile/`, `thumbs/`, `encoded-video/`.
  `ls -la ${UPLOAD_LOCATION}/`.

### DB_DATA_LOCATION

- **[REPO]** `.env.example` shows `DB_DATA_LOCATION=./postgres` (relative to `/opt/docker/composeyourself`).
- **[REPO]** `docker-compose.rocketman.yml` L190: `${DB_DATA_LOCATION}:/var/lib/postgresql/data`.
- `[LIVE]` Actual `DB_DATA_LOCATION` value from `.env`.
- `[LIVE]` `du -sh ${DB_DATA_LOCATION}` for DB size.

### Postgres version

- **[REPO] CONFIRMED:** Postgres 14 (`postgres:14-vectorchord0.4.3-pgvectors0.2.0`).
- `[LIVE]` `docker exec immich_postgres psql -U postgres -c "SELECT version();" | head -1`

### Total size of originals

- `[LIVE]` `du -sh ${UPLOAD_LOCATION}/library ${UPLOAD_LOCATION}/upload ${UPLOAD_LOCATION}/profile`
  (excluding `thumbs/` and `encoded-video/`).

### USB disk

- `[LIVE]` `lsblk -f` → device path, UUID, FSTYPE.
- `[LIVE]` Is it ext4? Mounted at `/mnt/backup`?
- `[LIVE]` `df -h /mnt/backup` → free space vs. library size.

### Installed tooling

- `[LIVE]` `borg --version` — expected on Ubuntu: `apt install borgbackup`
- `[LIVE]` `rclone version` — expected on Ubuntu: `apt install rclone` or from upstream .deb
- `[LIVE]` Install commands for Ubuntu (rocketman runs Ubuntu per systemd unit):
  ```bash
  sudo apt update && sudo apt install -y borgbackup rclone
  ```

### B2 credentials

- `[LIVE]` `rclone listremotes` — should show e.g. `b2:`
- `[LIVE]` `sudo rclone listremotes` (rclone config may live under dockerops or root)
- `[LIVE]` `rclone lsd b2:` to check bucket exists (DO NOT create)

### Existing backup cron/systemd units

- `[LIVE]` `systemctl list-timers | grep -i backup`
- `[LIVE]` `crontab -l -u root`, `crontab -l -u dockerops`
- `[LIVE]` `ls -la /etc/systemd/system/*backup*`

### Secrets directory permissions

- **[REPO]** Spec assumes:
  - `/etc/borg/passphrase` — mode 0400, owned root:root
  - `/root/.config/rclone/rclone.conf` — mode 0600, owned root:root
- `[LIVE]` `ls -la /etc/borg/`, `ls -la /root/.config/rclone/` — do dirs exist?

### Host OS

- **[REPO]** rocketman is a Raspberry Pi running Ubuntu (systemd unit targets `multi-user.target`).
- **[REPO]** Deploy user is `dockerops` with home `/opt/docker`.
- **[REPO]** Working directory for all compose operations: `/opt/docker/composeyourself`.

---

## Step 2 — Spec Reconciliation

| Spec assumption | Status | Notes |
|----------------|--------|-------|
| Immich runs in Docker Compose | **CONFIRMED** | `docker-compose.rocketman.yml` |
| Container name `immich_postgres` | **CONFIRMED** | L181 of rocketman compose |
| `UPLOAD_LOCATION` on `/mnt/storage` | `[LIVE]` | .env.example shows `./library`; real .env must be checked |
| Postgres 14 | **CONFIRMED** | Image tag `14-vectorchord0.4.3` |
| USB disk at `/mnt/backup`, ext4 | `[LIVE]` | Not yet confirmed; `lsblk` needed |
| borg available | `[LIVE]` | Package `borgbackup` in Ubuntu repos |
| rclone available | `[LIVE]` | Package `rclone` in Ubuntu repos |
| B2 bucket exists | `[LIVE]` | `rclone lsd b2:` needed |
| No existing backup timer conflicts | `[LIVE]` | Check `systemctl list-timers` |
| Secrets at `/etc/borg/`, `/root/.config/rclone/` | `[LIVE]` | Dirs must be created with correct perms |
| Host is Ubuntu on arm64 (Raspberry Pi) | **CONFIRMED** | Per systemd unit + GitHub workflow targets |

---

## Next Steps (human actions before Phase 2 can run)

Run the following on rocketman (as `dockerops` or `root`) and append results here:

```bash
# 1. Real path values
grep -E '^(UPLOAD_LOCATION|DB_DATA_LOCATION|IMMICH_VERSION)=' /opt/docker/composeyourself/.env

# 2. USB disk
lsblk -f
df -h /mnt/backup 2>/dev/null || echo "USB not mounted at /mnt/backup"

# 3. Toolchain
borg --version 2>/dev/null || echo "borg not installed"
rclone version 2>/dev/null || echo "rclone not installed"

# 4. B2
rclone listremotes 2>/dev/null || echo "no rclone config"

# 5. Library sizes
du -sh /mnt/storage/immich/library /mnt/storage/immich/upload /mnt/storage/immich/profile 2>/dev/null || \
du -sh /opt/docker/composeyourself/library/upload /opt/docker/composeyourself/library/library /opt/docker/composeyourself/library/profile 2>/dev/null

# 6. DB size
du -sh /mnt/storage/immich/postgres 2>/dev/null || \
du -sh /opt/docker/composeyourself/postgres 2>/dev/null

# 7. Existing timers
systemctl list-timers 2>/dev/null | grep -iE 'backup|borg|cron'
crontab -l -u root 2>/dev/null
crontab -l -u dockerops 2>/dev/null
```
