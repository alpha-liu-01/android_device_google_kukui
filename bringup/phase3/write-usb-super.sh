#!/bin/bash
# Rewrite only the USB super partition. Does not repartition and does not
# touch the kernel slot, the log partition, metadata, misc, or userdata.
set -euo pipefail
DISK=/dev/sdb
SUPER_IMG=${1:?need unsparsed super image}

[[ $(id -u) -eq 0 ]] || { echo "need root" >&2; exit 1; }
[[ $(findmnt -n -o SOURCE /) != /dev/sdb* ]] || { echo "workstation root is on sdb" >&2; exit 1; }
[[ -b $DISK ]] || { echo "no $DISK" >&2; exit 1; }
readlink -f "/sys/block/sdb/device" | grep -q /usb || { echo "sdb is not USB" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL ${DISK}1) == pmOS_kernel ]] || { echo "sdb1 is not pmOS_kernel" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL ${DISK}3) == super ]] || { echo "sdb3 is not super" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb1/start) == 8192 ]] || { echo "sdb1 start changed" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb3/start) == 1122304 ]] || { echo "sdb3 start changed" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb3/size) == 16777216 ]] || { echo "sdb3 size changed" >&2; exit 1; }
findmnt ${DISK}3 >/dev/null 2>&1 && { echo "sdb3 is mounted" >&2; exit 1; }

echo "target: ${DISK}3 super start 1122304 size 16777216"
sfdisk -d "$DISK"
img_bytes=$(stat -c %s "$SUPER_IMG")
[[ "$img_bytes" -eq $((16777216 * 512)) ]] || { echo "super image is not 8 GiB" >&2; exit 1; }

dd if="$SUPER_IMG" of=${DISK}3 bs=1048576 conv=fsync status=progress
echo "readback"
readback=$(dd if=${DISK}3 bs=1048576 status=none | sha256sum | awk '{print $1}')
expect=$(sha256sum "$SUPER_IMG" | awk '{print $1}')
[[ "$readback" == "$expect" ]] || { echo "readback $readback != $expect" >&2; exit 1; }
echo "OK $readback"
