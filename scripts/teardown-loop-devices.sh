#!/usr/bin/env bash
# Detaches loop devices and removes the sparse files. Run this after
# `kind delete cluster` when you want a totally clean slate.

set -euo pipefail
DISK_DIR="/var/lib/lakehouse-disks"

for dev in $(losetup -j "$DISK_DIR"/*.img 2>/dev/null | cut -d: -f1); do
  echo "Detaching $dev"
  sudo losetup -d "$dev"
done

echo "Removing $DISK_DIR"
rm -rf "$DISK_DIR"
echo "Done."
