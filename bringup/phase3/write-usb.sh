#!/bin/bash
# Replace the USB pmOS_root partition with super, metadata, misc, and userdata.
# Prints the table first. Refuses anything that is not this USB stick.
set -euo pipefail
DISK=/dev/sdb
SUPER_IMG=${1:?need unsparsed super image}
SGDISK=/run/media/alpha/YMTC/lineage-23.2/out/host/linux-x86/bin/sgdisk

[[ $(id -u) -eq 0 ]] || { echo "need root" >&2; exit 1; }
[[ $(findmnt -n -o SOURCE /) != /dev/sdb* ]] || { echo "workstation root is on sdb" >&2; exit 1; }
[[ -b $DISK ]] || { echo "no $DISK" >&2; exit 1; }
readlink -f "/sys/block/sdb/device" | grep -q /usb || { echo "sdb is not USB" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL ${DISK}1) == pmOS_kernel ]] || { echo "sdb1 is not pmOS_kernel" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL ${DISK}2) == pmOS_boot ]] || { echo "sdb2 is not pmOS_boot" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb1/start) == 8192 ]] || { echo "sdb1 start changed" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb1/size) == 65536 ]] || { echo "sdb1 size changed" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb2/start) == 73728 ]] || { echo "sdb2 start changed" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb3/start) == 1122304 ]] || { echo "sdb3 start is not the old root" >&2; exit 1; }
findmnt "$DISK" >/dev/null 2>&1 && { echo "$DISK is mounted" >&2; exit 1; }
for p in ${DISK}1 ${DISK}2 ${DISK}3; do
    findmnt "$p" >/dev/null 2>&1 && { echo "$p is mounted" >&2; exit 1; }
done

echo "before:"
sfdisk -d "$DISK"
echo "plan: keep sdb1 pmOS_kernel and sdb2 pmOS_boot"
echo "sdb3 super     1122304 +16777216"
echo "sdb4 metadata 17899520 +32768"
echo "sdb5 misc     17932288 +8192"
echo "sdb6 userdata 17940480 through 122167262"

img_bytes=$(stat -c %s "$SUPER_IMG")
[[ "$img_bytes" -le $((16777216 * 512)) ]] || { echo "super image does not fit" >&2; exit 1; }

"$SGDISK" --delete=3 "$DISK"
"$SGDISK" \
    --new=3:1122304:17899519 --change-name=3:super \
    --new=4:17899520:17932287 --change-name=4:metadata \
    --new=5:17932288:17940479 --change-name=5:misc \
    --new=6:17940480:122167262 --change-name=6:userdata \
    "$DISK"
partprobe "$DISK"
udevadm settle

echo "after:"
sfdisk -d "$DISK"
[[ $(blkid -o value -s PARTLABEL ${DISK}3) == super ]] || { echo "sdb3 name" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL ${DISK}2) == pmOS_boot ]] || { echo "sdb2 moved" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb1/start) == 8192 ]] || { echo "sdb1 moved" >&2; exit 1; }

dd if="$SUPER_IMG" of=${DISK}3 bs=4096 conv=fsync status=progress
echo OK
