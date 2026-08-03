# Monthly SMART self-check for the Immich backup USB disk
# Install via root crontab:
#   sudo crontab -e
# Add line (runs first Sunday of each month at 03:00):
#   0 3 * * 0 [ $(date +\%d) -le 7 ] && /opt/docker/composeyourself/docs/plans/immich-backup-phase1/smart-check.sh
#
# Or as a systemd timer (recommended — consistent with rest of stack):
#   See immich-backup-smart-mon.service + .timer below.

# smart-check.sh — runs a short SMART self-test on the USB backup disk.
# Device path from: lsblk -o NAME,MOUNTPOINT | grep /mnt/backup | awk '{print "/dev/"$1}'

#!/bin/bash
set -euo pipefail

DISK="/dev/REPLACE_ME_USB_DEVICE"  # e.g. /dev/sda (whole disk, not sda1)

if [ ! -b "$DISK" ]; then
    echo "[$(date)] FATAL: device ${DISK} not found" | systemd-cat -t immich-backup-smart
    exit 1
fi

echo "[$(date)] Starting SMART short test on ${DISK}" | systemd-cat -t immich-backup-smart
smartctl -t short "$DISK"

echo "[$(date)] SMART test results for ${DISK}:" | systemd-cat -t immich-backup-smart
smartctl -H "$DISK" | systemd-cat -t immich-backup-smart
smartctl -A "$DISK" | systemd-cat -t immich-backup-smart
