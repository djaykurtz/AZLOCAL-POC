#!/usr/bin/env bash
# Format and mount the attached cluster data disk. Refuses to touch a disk that already
# carries a filesystem, so re-running it is safe.
set -euo pipefail

DEV=/dev/sdb
MNT=/srv/data

if [ ! -b "$DEV" ]; then
  echo "ABORT: $DEV is not a block device"
  exit 1
fi

if [ -n "$(sudo blkid "$DEV" 2>/dev/null || true)" ]; then
  echo "ALREADY PROVISIONED, leaving it alone:"
  sudo blkid "$DEV"
  df -h "$MNT" 2>/dev/null | tail -1 || true
  exit 0
fi

if mount | grep -q "^$DEV"; then
  echo "ABORT: $DEV is mounted"
  exit 1
fi

echo "formatting $DEV as xfs ..."
sudo mkfs.xfs -q -L clusterdata "$DEV"
sudo mkdir -p "$MNT"

UUID="$(sudo blkid -s UUID -o value "$DEV")"
if ! grep -q "$UUID" /etc/fstab; then
  # nofail so a missing disk never blocks boot, UUID so device order cannot break it
  echo "UUID=$UUID $MNT xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab > /dev/null
fi

sudo mount -a
sudo chown azureuser:azureuser "$MNT"

echo "=== mounted ==="
df -h "$MNT" | tail -1
echo "=== fstab entry ==="
grep "$UUID" /etc/fstab
echo "=== write test ==="
echo ok > "$MNT/.write-test" && rm -f "$MNT/.write-test" && echo "read/write confirmed"
