#!/bin/bash
# Write the phase 3 depthcharge image to the USB kernel slot only.
set -euo pipefail
IMG=${1:?need kernel.kpart}
DEV=/dev/sdb1
EXPECT=$(sha256sum "$IMG" | awk '{print $1}')

[[ $(id -u) -eq 0 ]] || { echo "need root" >&2; exit 1; }
[[ $(findmnt -n -o SOURCE /) != /dev/sdb* ]] || { echo "workstation root is on sdb" >&2; exit 1; }
readlink -f /sys/block/sdb/device | grep -q /usb || { echo "sdb is not USB" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL "$DEV") == pmOS_kernel ]] || { echo "not pmOS_kernel" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb1/start) == 8192 ]] || { echo "start changed" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb1/size) == 65536 ]] || { echo "size changed" >&2; exit 1; }
bytes=$(stat -c %s "$IMG")
[[ "$bytes" -le $((65536 * 512)) ]] || { echo "image does not fit in 32 MiB" >&2; exit 1; }
findmnt "$DEV" >/dev/null 2>&1 && { echo "$DEV is mounted" >&2; exit 1; }

echo "writing $bytes bytes sha256 $EXPECT to $DEV"
dd if="$IMG" of="$DEV" bs=4096 conv=fsync status=progress
readback=$(dd if="$DEV" bs=4096 count=$(((bytes + 4095) / 4096)) status=none | sha256sum | awk '{print $1}')
# hash only the image length, not the padding in the last block
readback=$(dd if="$DEV" bs=1 count="$bytes" status=none | sha256sum | awk '{print $1}')
[[ "$readback" == "$EXPECT" ]] || { echo "readback $readback" >&2; exit 1; }
echo OK "$EXPECT"
