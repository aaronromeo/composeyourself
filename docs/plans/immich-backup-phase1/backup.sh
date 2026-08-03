#!/bin/bash
# Immich → Borg → Backblaze B2 nightly backup pipeline
# Set -e exits on first failure; -u treats unset vars as errors; -o pipefail
# catches failures inside pipes (e.g. pg_dump | gzip).
set -euo pipefail

###############################################################################
# Load Immich .env for DB creds (safe: only exports vars, no eval)           #
###############################################################################
ENV_FILE="/opt/docker/composeyourself/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    . "$ENV_FILE"
    set +a
fi

###############################################################################
# CONFIGURATION — set by Phase 2 from live box findings                      #
###############################################################################
BORG_REPO="/mnt/backup/borg-immich"
STAGING="/mnt/backup/immich-staging"
UPLOAD_LOCATION="REPLACE_ME_UPLOAD_LOCATION"
DB_CONTAINER="immich_postgres"
DB_NAME="${DB_DATABASE_NAME:-immich}"
DB_USER="${DB_USERNAME:-postgres}"
RCLONE_REMOTE="b2:immich-backup"
LOG_FILE="/var/log/immich-backup.log"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DB_DUMP="${STAGING}/immich_db_${TIMESTAMP}.sql.gz"

###############################################################################
# HELPER: log a timestamped message to stdout and LOG_FILE                   #
###############################################################################
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

###############################################################################
# GUARD: refuse to run if /mnt/backup is not mounted (protect against        #
# writing to the SD card's /mnt/backup directory when USB is absent)         #
###############################################################################
if ! mountpoint -q /mnt/backup; then
    log "FATAL: /mnt/backup is not mounted. USB disk absent? Aborting."
    exit 1
fi

###############################################################################
# STEP 1 — pg_dump Postgres → timestamped .sql.gz in staging dir            #
###############################################################################
log "Starting Immich backup (timestamp: ${TIMESTAMP})"

mkdir -p "$STAGING"

log "Dumping Postgres database ${DB_NAME}..."

if ! docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$DB_DUMP"; then
    log "FATAL: pg_dump failed."
    exit 1
fi

dump_size=$(du -h "$DB_DUMP" | cut -f1)
log "DB dump created: ${DB_DUMP} (${dump_size})"

###############################################################################
# STEP 2 — borg create (files + staging, one archive per run)               #
###############################################################################
export BORG_REPO
export BORG_PASSCOMMAND="cat /etc/borg/passphrase"

log "Creating Borg archive immich-${TIMESTAMP}..."
borg create \
    --compression lz4 \
    --exclude '*/thumbs' \
    --exclude '*/encoded-video' \
    --stats \
    "::immich-${TIMESTAMP}" \
    "$STAGING" \
    "${UPLOAD_LOCATION}/library" \
    "${UPLOAD_LOCATION}/upload" \
    "${UPLOAD_LOCATION}/profile"

borg_exit=$?
if [ $borg_exit -ne 0 ]; then
    log "FATAL: borg create exited with code ${borg_exit}."
    exit 1
fi

###############################################################################
# STEP 3 — borg prune (retention: 14 daily, 8 weekly, 12 monthly)           #
###############################################################################
log "Pruning old archives..."
borg prune \
    --keep-daily 14 \
    --keep-weekly 8 \
    --keep-monthly 12 \
    --stats

prune_exit=$?
if [ $prune_exit -ne 0 ]; then
    log "WARNING: borg prune exited with code ${prune_exit} (non-fatal)."
fi

###############################################################################
# STEP 4 — borg compact (reclaim space after pruning)                        #
###############################################################################
log "Compacting repository..."
borg compact

compact_exit=$?
if [ $compact_exit -ne 0 ]; then
    log "WARNING: borg compact exited with code ${compact_exit} (non-fatal)."
fi

###############################################################################
# STEP 5 — rclone sync → Backblaze B2 (passive replica, prunes propagate)   #
###############################################################################
log "Syncing Borg repo to Backblaze B2..."
# --fast-list uses fewer API calls (B2 charges per call)
rclone sync "$BORG_REPO" "$RCLONE_REMOTE" \
    --fast-list \
    --verbose \
    --stats 30s

rclone_exit=$?
if [ $rclone_exit -ne 0 ]; then
    log "FATAL: rclone sync exited with code ${rclone_exit}."
    exit 1
fi

###############################################################################
# STEP 6 — clean staging (dump already archived)                            #
###############################################################################
log "Cleaning staging directory..."
rm -f "$DB_DUMP"
rmdir --ignore-fail-on-non-empty "$STAGING" 2>/dev/null || true

unset BORG_REPO
unset BORG_PASSCOMMAND

log "Backup complete: immich-${TIMESTAMP}"
log "---"
