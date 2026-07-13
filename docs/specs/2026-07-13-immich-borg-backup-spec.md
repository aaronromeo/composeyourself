# Immich → Backblaze B2 Backup — Spec

**Date:** 2026-07-13
**Host:** rocketman (Ubuntu, Immich via Docker Compose)
**Strategy:** 3-2-1 via Borg (local, authoritative) + rclone sync to Backblaze B2 (off-site replica)

---

## Purpose

Automated, verifiable, production-grade backup of a self-hosted Immich instance,
with point-in-time history and a proven restore path. This spec defines *what
"backed up" means* and *how we know a backup is good* — not the exact commands
(those are generated in Phase 1 against the live box; see the inspection doc).

## What gets backed up (one unit, always together)

| Part | Source | Why |
|------|--------|-----|
| **Database** | `pg_dump`/`pg_dumpall` of the running `immich_postgres` container → timestamped gzipped `.sql.gz` in a staging dir | Album structure, metadata, users, ML/face data, sharing. Useless without files. |
| **Files** | `UPLOAD_LOCATION` — `library/`, `upload/`, `profile/` (originals) | The actual photos/videos. Useless without the DB. |

**The DB dump is included in the same Borg archive as the files**, so every
archive is self-contained and restorable to a single consistent point in time.

**Deliberately excluded** (Immich docs confirm regenerable): `thumbs/`,
`encoded-video/`. Saves storage; regenerated on restore.

**Never backed up:** Redis (ephemeral). Never copy the live Postgres data
directory while the DB is running — dump only.

## Architecture

```
Immich (Docker Compose)
   ├── pg_dump ─────────────► staging/*.sql.gz ─┐
   └── UPLOAD_LOCATION (RO) ─────────────────────┤
                                                  ▼
                              ┌─────────────────────────────┐
                              │ Borg repo on USB (/mnt/backup)│  authoritative
                              │ encrypted · dedup · history   │
                              └─────────────────────────────┘
                                                  │ rclone sync
                                                  ▼
                              ┌─────────────────────────────┐
                              │ Backblaze B2                 │  off-site replica
                              │ (dumb file mirror of repo)   │
                              └─────────────────────────────┘
```

- **USB Borg repo is authoritative; B2 is a passive replica.** `rclone sync`
  (not `copy`) so prunes propagate.
- Borg local → both legs are eyeball-verifiable: `borg check`/`borg list`
  locally; file-tree compare on B2.

## Retention

`borg prune`: keep-daily 14, keep-weekly 8, keep-monthly 12. Cross-archive
dedup means 30+ days of history costs ~one library + deltas (a photo library
grows more than it churns).

## Encryption & the passphrase (the sharpest edge)

- Repo encryption: `repokey-blake2` (or equivalent).
- Passphrase in a **root-only** file (e.g. `/etc/borg/passphrase`), referenced
  via `BORG_PASSCOMMAND`.
- **Losing the passphrase = losing every backup.** The plan MUST include an
  explicit human step: record the passphrase off-machine before proceeding.
- USB filesystem itself is not separately encrypted — Borg handles encryption.

## Scheduling & safety

- Nightly via **systemd service + timer** (preferred over cron).
- Execution order: (1) dump Postgres → staging, (2) `borg create` (files +
  staging), (3) `borg prune`, (4) `borg compact`, (5) `rclone sync` → B2,
  (6) clean staging.
- Script: `set -euo pipefail`, timestamped log to `/var/log/immich-backup.log`,
  non-zero exit on any failure, idempotent, never deletes source data.
- Refuse to run if `/mnt/backup` is not mounted (USB mounted by UUID in
  `/etc/fstab` with `nofail`).
- Failure surfaced via systemd `OnFailure=` (ntfy/email hook recommended).
- Monthly SMART check on the USB disk.

## Restore success criteria (what makes a backup "good")

A backup is proven ONLY if a restore works end-to-end. **Before the nightly
timer is armed**, Phase 2 must:

1. Extract an archive to a scratch location (`borg extract`).
2. Load the DB dump into a fresh/throwaway Immich stack.
3. Point that stack at the extracted files.
4. Confirm assets render and album/metadata are intact.

The restore runbook (`restore.md`) must cover both USB (`borg list`/`extract`)
and B2 (`rclone copy` repo back, then `borg extract`) paths, plus loading the
Postgres dump into a fresh stack and verifying integrity.

## Non-goals

- No Redis backup. No derived-asset backup (thumbs/encoded). No multi-host Borg
  access. No separate USB filesystem encryption.

## Deliverables (produced in Phase 1 on the box)

1. `/etc/fstab` entry for USB (UUID, `nofail`)
2. Borg repo init commands (encrypted)
3. rclone B2 config guidance
4. `backup.sh` — full pipeline
5. systemd service + timer units
6. `restore.md` runbook
7. Monthly SMART-check command/cron
