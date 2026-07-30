#!/usr/bin/env bash
# Creates 3 sparse files + loop devices to back Ceph OSDs (via local PersistentVolumes —
# see apps/rook-ceph-cluster/manifests/local-storage.yaml), then generates
# kind/cluster-config.yaml from the template.
#
# Uses FIXED high loop device numbers (30/31/32) rather than letting the kernel
# auto-pick one (`losetup -f`). Auto-pick sounds convenient but this project hit
# real problems with it: snapd already owns loop0-20 on most Ubuntu systems, and
# after repeated create/delete cycles the kernel can get into a state where a
# low auto-picked minor is "lost" (allocated internally but with no usable device
# node) or gets clobbered by Docker silently creating a placeholder directory at
# that path. Fixed high numbers sidestep all of that.
#
# Run this ONCE before `kind create cluster`. Needs sudo.
#
# Disk size: 10G sparse (doesn't actually consume 10G on disk until written).

set -euo pipefail

DISK_DIR="/var/lib/lakehouse-disks"
DISK_SIZE="10G"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOOP_NUMS=(30 31 32)

sudo mkdir -p "$DISK_DIR"
sudo chown "${SUDO_USER:-$(whoami)}" "$DISK_DIR"

sudo udevadm trigger --subsystem-match=block 2>/dev/null || true
sudo udevadm settle 2>/dev/null || true

LOOP_DEVICES=()
for i in 0 1 2; do
  IMG="$DISK_DIR/disk${i}.img"
  LOOP_NUM="${LOOP_NUMS[$i]}"
  LOOP_DEV="/dev/loop${LOOP_NUM}"

  if [ ! -f "$IMG" ]; then
    echo "Creating sparse file $IMG ($DISK_SIZE)..."
    truncate -s "$DISK_SIZE" "$IMG"
  fi

  if [ -d "$LOOP_DEV" ]; then
    echo "$LOOP_DEV is a stray directory, not a device — removing it"
    sudo rmdir "$LOOP_DEV"
  fi

  if [ ! -e "$LOOP_DEV" ]; then
    echo "Creating device node $LOOP_DEV"
    sudo mknod -m 660 "$LOOP_DEV" b 7 "$LOOP_NUM"
    sudo chgrp disk "$LOOP_DEV"
  fi

  EXISTING_LOOP=$(sudo losetup -j "$IMG" | cut -d: -f1)
  if [ "$EXISTING_LOOP" = "$LOOP_DEV" ]; then
    echo "$IMG is already attached to $LOOP_DEV, reusing it"
  else
    sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
    echo "Attaching $IMG to $LOOP_DEV"
    sudo losetup "$LOOP_DEV" "$IMG"
  fi
  LOOP_DEVICES+=("$LOOP_DEV")
done

echo ""
echo "Loop devices ready: ${LOOP_DEVICES[*]}"

sed -e "s|LOOP0_DEV|${LOOP_DEVICES[0]}|" \
    -e "s|LOOP1_DEV|${LOOP_DEVICES[1]}|" \
    -e "s|LOOP2_DEV|${LOOP_DEVICES[2]}|" \
    "$REPO_ROOT/kind/cluster-config.yaml.tmpl" > "$REPO_ROOT/kind/cluster-config.yaml"

echo "Generated kind/cluster-config.yaml with real loop device paths."
echo ""
echo "IMPORTANT: these loop devices don't survive a host reboot. If you reboot,"
echo "re-run this script BEFORE re-creating the kind cluster."
