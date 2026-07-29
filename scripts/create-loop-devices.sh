#!/usr/bin/env bash
# Creates 3 sparse files + loop devices to simulate raw disks for Rook-Ceph OSDs,
# then generates kind/cluster-config.yaml from the template with the real
# /dev/loopN paths the kernel assigned (these numbers are dynamic, not fixed).
#
# Run this ONCE before `kind create cluster`. Needs sudo for losetup.
#
# Disk size: 10G sparse (doesn't actually consume 10G on disk until written).
# Bump DISK_SIZE if you want more headroom for testing bigger Iceberg tables.

set -euo pipefail

DISK_DIR="/var/lib/lakehouse-disks"
DISK_SIZE="10G"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sudo mkdir -p "$DISK_DIR"
sudo chown "$(whoami)" "$DISK_DIR"

LOOP_DEVICES=()
for i in 0 1 2; do
  IMG="$DISK_DIR/disk${i}.img"
  if [ ! -f "$IMG" ]; then
    echo "Creating sparse file $IMG ($DISK_SIZE)..."
    truncate -s "$DISK_SIZE" "$IMG"
  fi

  LOOP_DEV=$(sudo losetup -f)
  echo "Attaching $IMG to $LOOP_DEV"
  sudo losetup "$LOOP_DEV" "$IMG"
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
echo "re-run this script BEFORE re-creating the kind cluster. To clean up entirely,"
echo "run scripts/teardown-loop-devices.sh."
