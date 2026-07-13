# Phase 1 — Inspection & Plan Generation (Opus, on rocketman via OpenCode)

**Date:** 2026-07-13
**Companion to:** `2026-07-13-immich-borg-backup-spec.md`

This is the prompt/checklist for the **expensive** phase. Run it with Opus in
OpenCode *on rocketman*. Its job: inspect the live box, reconcile findings
against the spec, then author an executable checklist + artifacts for a cheap
model to run.

---

## Hard rules for Phase 1

- **READ-ONLY on live state. WRITE-ONLY to new files.** You may inspect, list,
  `cat`, `docker inspect`, `du`, `df`, `lsblk`, `borg --version`, etc. You may
  write spec/plan/artifact files into a working dir. You must **NOT** run:
  `borg init`, `borg create`, `rclone sync`, any `pg_dump`, any mount/fstab
  edit, any systemd enable, or anything that changes system state. All mutation
  belongs to Phase 2.
- **Never guess a path or name.** If the box contradicts the spec, STOP and
  record the mismatch in `findings.md` — do not silently adapt.

## Step 1 — Inspect (record everything into `findings.md`)

Gather and write down:

- [ ] Immich version and how it runs (compose file location — spec says
      `/opt/docker/composeyourself`; confirm).
- [ ] Container names (spec assumes `immich_postgres`; confirm actual name).
- [ ] `UPLOAD_LOCATION` actual path (spec says on `/mnt/storage`; confirm) and
      its subdirs (`library/`, `upload/`, `profile/`, `thumbs/`, `encoded-video/`).
- [ ] `DB_DATA_LOCATION`, Postgres version, DB size (`du -sh`).
- [ ] Total size of originals to back up (`du -sh` excluding thumbs/encoded).
- [ ] USB disk: present? `lsblk -f` → device, UUID, filesystem. Is it ext4?
      Mounted at `/mnt/backup`? Free space vs. library size.
- [ ] Installed tooling: `borg --version`, `rclone version` — present or need
      install? Record install method for the target OS.
- [ ] B2 credentials present? rclone remote configured
      (`rclone listremotes`)? B2 bucket exists? (Do NOT create it.)
- [ ] Existing backup cron/systemd units that might conflict.
- [ ] Where secrets should live (`/etc/borg/`, `/root/.config/rclone/`) — perms.

## Step 2 — Reconcile against the spec

For each spec assumption, mark CONFIRMED / DIFFERENT / MISSING in `findings.md`.
Any DIFFERENT or MISSING that blocks the plan → flag prominently at the top.

## Step 3 — Author artifacts (write files; do not execute)

Generate, using the confirmed live values (no placeholders — real paths):

- [ ] `plan.md` — the Phase 2 checklist. **Write to the most defensive
      standard: assume a mid-tier open-weight model with no judgment.** Rules
      for plan.md:
    - Numbered, linear steps. One action per step.
    - Every step = an **exact command** (copy-pasteable, real values) followed
      by an **exact expected result** ("verify output contains `encryption:
      repokey-blake2`").
    - Every step has a **STOP condition**: "If output differs, STOP and report.
      Do not continue, do not improvise, do not retry with different flags."
    - No step says "configure X" — it says exactly which keystrokes.
    - Order matches spec §scheduling: fstab/mount → verify mount → install tools
      → borg init → **record passphrase off-machine (HUMAN step, blocking)** →
      first `borg create` → `borg check`/`list` verify → `rclone sync` → B2
      file-tree compare verify → **scratch restore test (blocking gate)** →
      only then install + enable systemd timer → confirm timer scheduled.
    - The scratch-restore test (spec restore criteria) is a **hard gate before
      arming the timer** — mark it clearly.
- [ ] `backup.sh` — full pipeline, `set -euo pipefail`, logging, mount guard,
      exec order per spec. Referenced by plan.md, installed (not run) in Phase 2.
- [ ] systemd `.service` + `.timer` units (nightly).
- [ ] `/etc/fstab` line (real UUID from Step 1, `nofail`).
- [ ] `restore.md` runbook (USB + B2 paths, DB load, integrity verify).
- [ ] SMART-check command/cron for the USB disk.

## Step 4 — Handoff

- [ ] Summarize at the top of `plan.md`: what Phase 2 will change, the two
      blocking human/gate steps (passphrase record; scratch-restore before arm),
      and the model it's written for.
- [ ] STOP. Hand `spec.md` + `plan.md` + artifacts to the human for review
      before Phase 2 runs anything.

---

## Then: trust gate → Phase 2

Human reviews `spec.md` + `plan.md`. On approval, a **mid-tier open-weight
model** (via OpenRouter or OpenCode Zen) runs `plan.md` step-by-step: run exact
command → check expected result → tick box → STOP on any mismatch. It does all
mutation; it makes no decisions.
