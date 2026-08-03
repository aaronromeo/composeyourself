# Restore Runbook — Immich from Borg backup

This runbook covers both USB-local and Backblaze B2 remote restore paths.
All commands run as root on rocketman.

---

## Prerequisites

- The Borg passphrase at `/etc/borg/passphrase`.
- Borg and rclone installed (already checked in Phase 1).
- The USB disk mounted at `/mnt/backup` (for USB restore) **or** rclone
  configured with B2 credentials (for B2 restore).

---

## Path A — Restore from USB (borg local)

### A1. Verify the repository

```bash
export BORG_REPO=/mnt/backup/borg-immich
export BORG_PASSCOMMAND="cat /etc/borg/passphrase"

borg list
```
Expected: list of archives named `immich-YYYYMMDD_HHMMSS`.

### A2. Check repository integrity

```bash
borg check
```
Expected: no errors. If errors, try `borg check --repair` (docs warn this is
a last resort — confirm with a human first).

### A3. Extract a specific archive to a scratch location

```bash
ARCHIVE="immich-YYYYMMDD_HHMMSS"  # pick one from `borg list`
RESTORE_ROOT="/tmp/immich-restore"
mkdir -p "$RESTORE_ROOT"

borg extract "::${ARCHIVE}" --destination "$RESTORE_ROOT"
```
Expected: files extracted. The layout under `$RESTORE_ROOT` mirrors what was
backed up:
```
/tmp/immich-restore/
  mnt/backup/immich-staging/immich_db_<timestamp>.sql.gz
  UPLOAD_LOCATION/library/...
  UPLOAD_LOCATION/upload/...
  UPLOAD_LOCATION/profile/...
```

### A4. Load the database dump into a fresh Immich stack

```bash
# Locate the .sql.gz file
DB_DUMP=$(ls "$RESTORE_ROOT"/mnt/backup/immich-staging/immich_db_*.sql.gz | tail -1)

# Load into a throwaway Immich postgres container
gunzip -c "$DB_DUMP" | docker exec -i immich_postgres psql -U postgres
```
Expected: `psql` completes without error. Verify table count:
```bash
docker exec immich_postgres psql -U postgres -d immich -c "SELECT count(*) FROM pg_tables WHERE schemaname='public';"
```

### A5. Point Immich at the restored files

If restoring to the same Immich instance: stop the `immich-server` container,
move the existing `${UPLOAD_LOCATION}` aside, and copy the extracted
`library/`, `upload/`, `profile/` directories in its place. Restart
`immich-server`.

```bash
docker stop immich_server
mv "${UPLOAD_LOCATION}" "${UPLOAD_LOCATION}.old"
cp -a "$RESTORE_ROOT/${UPLOAD_LOCATION#/}/library" "${UPLOAD_LOCATION}/library"
cp -a "$RESTORE_ROOT/${UPLOAD_LOCATION#/}/upload"  "${UPLOAD_LOCATION}/upload"
cp -a "$RESTORE_ROOT/${UPLOAD_LOCATION#/}/profile" "${UPLOAD_LOCATION}/profile"
docker start immich_server
```

### A6. Verify restore

1. Open Immich UI. Confirm assets render (thumbnails regenerate automatically).
2. Spot-check album structure and metadata.
3. Run `docker exec immich_postgres psql -U postgres -d immich -c "SELECT count(*) FROM assets;"`.
   Compare with pre-restore count if known.

---

## Path B — Restore from Backblaze B2 (off-site)

### B1. Download the Borg repo from B2

```bash
B2_REMOTE="b2:immich-backup"
LOCAL_COPY="/mnt/backup/borg-immich-restored"
mkdir -p "$LOCAL_COPY"

rclone copy "$B2_REMOTE" "$LOCAL_COPY" --fast-list --verbose
```
Expected: files copied. Compare file count:
```bash
rclone size "$B2_REMOTE"
du -sh "$LOCAL_COPY"
```

### B2. Use the downloaded repo as the Borg source

```bash
export BORG_REPO="$LOCAL_COPY"
export BORG_PASSCOMMAND="cat /etc/borg/passphrase"

borg list
borg check
borg extract ::immich-YYYYMMDD_HHMMSS --destination /tmp/immich-restore-b2
```

Then follow Path A steps A4–A6.

---

## Post-restore cleanup

```bash
rm -rf /tmp/immich-restore
rm -rf /tmp/immich-restore-b2
# Remove the downloaded B2 copy if no longer needed:
rm -rf /mnt/backup/borg-immich-restored
```

---

## Emergency notes

- **Losing `/etc/borg/passphrase` = losing all backups.** Ensure it is stored
  off-machine (password manager, printed, etc.).
- **B2 versioning:** `rclone sync` propagates deletes. If a `borg prune` deletes
  archives and then `rclone sync` runs, those archives are gone from B2 too.
  B2 bucket-level versioning (if enabled) can recover from accidental syncs —
  check the B2 bucket settings.
- **If both USB and B2 are unavailable:** You have no backups. This is why the
  spec mandates both local and off-site copies.
