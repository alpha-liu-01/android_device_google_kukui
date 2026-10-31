#!/bin/bash
# Write a bootable Kukui layout onto the empty DDR200 SanDisk in the
# Generic reader. Refuses the YMTC build disk and any other USB disk.
set -euo pipefail

SUPER_IMG=${1:?need unsparsed super image}
KERNEL_IMG=${2:?need kernel.kpart}
BYID=/dev/disk/by-id/usb-Generic_MassStorageClass_000000002959-0:0
YMTC=/dev/disk/by-id/usb-NVME_USB_3.2_0123456789ABC-0:0
SGDISK=/run/media/alpha/YMTC/lineage-23.2/out/host/linux-x86/bin/sgdisk
KERNEL_SHA=0fe8a90405415e72ec7a3cf51abe290cf0fc2ce4ad63d9bb2da51f5ab6aea1fb
# priority 15, tries 15, successful 1. Depthcharge ignores a kernel slot
# without these attribute bits.
ATTR=0x01ff000000000000

[[ $(id -u) -eq 0 ]] || { echo "need root" >&2; exit 1; }
[[ -b $BYID ]] || { echo "Sandisk reader is not plugged in" >&2; exit 1; }
[[ -b $YMTC ]] || { echo "YMTC disk missing; refusing to guess" >&2; exit 1; }

DISK=$(readlink -f "$BYID")
YMTC_DISK=$(readlink -f "$YMTC")
NAME=${DISK#/dev/}
[[ $DISK != "$YMTC_DISK" ]] || { echo "resolved to the YMTC disk" >&2; exit 1; }
[[ $NAME != nvme* ]] || { echo "resolved to nvme" >&2; exit 1; }
readlink -f "/sys/block/$NAME/device" | grep -q /usb || { echo "$DISK is not USB" >&2; exit 1; }
[[ $(findmnt -n -o SOURCE /) != "$DISK"* ]] || { echo "workstation root is on $DISK" >&2; exit 1; }
[[ $(cat /sys/block/$NAME/size) -ge 240000000 && $(cat /sys/block/$NAME/size) -le 260000000 ]] || {
    echo "disk size is not the 119G card" >&2
    exit 1
}
udevadm info -q property -n "$DISK" | grep -qx 'ID_SERIAL=Generic_MassStorageClass_000000002959-0:0' || {
    echo "serial does not match the Sandisk reader" >&2
    exit 1
}

for node in $(lsblk -ln -o NAME "$DISK"); do
    findmnt "/dev/$node" >/dev/null 2>&1 && { echo "/dev/$node is mounted" >&2; exit 1; }
done

img_bytes=$(stat -c %s "$SUPER_IMG")
[[ "$img_bytes" -eq $((16777216 * 512)) ]] || { echo "super image is not 8 GiB" >&2; exit 1; }
kern_bytes=$(stat -c %s "$KERNEL_IMG")
[[ "$kern_bytes" -eq 12513280 ]] || { echo "kernel.kpart size changed" >&2; exit 1; }
kern_sha=$(sha256sum "$KERNEL_IMG" | awk '{print $1}')
[[ "$kern_sha" == "$KERNEL_SHA" ]] || { echo "kernel.kpart hash changed" >&2; exit 1; }

echo "target $DISK ($NAME) serial 000000002959"
echo "before:"
sfdisk -d "$DISK" || true

"$SGDISK" --zap-all "$DISK"
"$SGDISK" \
    --new=1:8192:73727 --change-name=1:pmOS_kernel --typecode=1:FE3A2A5D-4F32-41A7-B725-ACCC3285A309 \
    --new=2:73728:1122303 --change-name=2:pmOS_boot --typecode=2:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new=3:1122304:17899519 --change-name=3:super --typecode=3:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new=4:17899520:17932287 --change-name=4:metadata --typecode=4:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new=5:17932288:17940479 --change-name=5:misc --typecode=5:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new=6:17940480:0 --change-name=6:userdata --typecode=6:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    "$DISK"

# sgdisk bit numbers are the GPT attribute bits. Set priority, tries, and
# successful, then read the entry back. A wrong numbering fails the script
# before any image is written.
"$SGDISK" \
    --attributes=1:set:48 --attributes=1:set:49 --attributes=1:set:50 --attributes=1:set:51 \
    --attributes=1:set:52 --attributes=1:set:53 --attributes=1:set:54 --attributes=1:set:55 \
    --attributes=1:set:56 \
    "$DISK"

python3 - "$DISK" "$ATTR" <<'PY'
import struct, sys
path, want = sys.argv[1], int(sys.argv[2], 16)
with open(path, "rb") as f:
    f.seek(512)
    header = f.read(512)
entry_lba, entry_size = struct.unpack_from("<QI", header, 72)
with open(path, "rb") as f:
    f.seek(entry_lba * 512)
    entry = f.read(entry_size)
got = struct.unpack_from("<Q", entry, 48)[0]
print(f"kernel attributes {got:#018x}")
if got != want:
    sys.exit("kernel attributes are not priority 15 / tries 15 / successful")
PY

partprobe "$DISK"
udevadm settle
P1=${BYID}-part1
P2=${BYID}-part2
P3=${BYID}-part3
[[ -b $P1 && -b $P2 && -b $P3 ]] || { echo "partition nodes missing" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL "$P1") == pmOS_kernel ]] || { echo "p1 name" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL "$P2") == pmOS_boot ]] || { echo "p2 name" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL "$P3") == super ]] || { echo "p3 name" >&2; exit 1; }
[[ $(cat /sys/class/block/${NAME}1/start) == 8192 ]] || { echo "p1 start" >&2; exit 1; }
[[ $(cat /sys/class/block/${NAME}3/start) == 1122304 ]] || { echo "p3 start" >&2; exit 1; }
[[ $(cat /sys/class/block/${NAME}3/size) == 16777216 ]] || { echo "p3 size" >&2; exit 1; }

echo "kernel"
dd if="$KERNEL_IMG" of="$P1" bs=1048576 conv=fsync status=progress
echo "boot log filesystem"
mkfs.ext4 -F -L pmOS_boot -E lazy_itable_init=0,lazy_journal_init=0 "$P2"
# Android only formats a formattable partition when the first 4 KiB is all
# 0x00 or all 0xff. Leftover bytes from the previous filesystem are treated
# as unknown data and left unformatted, so /data stays the read-only system
# image and init reboots.
echo "wipe metadata misc userdata headers"
for part in ${BYID}-part4 ${BYID}-part5 ${BYID}-part6; do
    dd if=/dev/zero of="$part" bs=1048576 count=1 conv=fsync status=none
done
echo "super"
dd if="$SUPER_IMG" of="$P3" bs=1048576 conv=fsync status=progress
echo "readback"
readback=$(dd if="$P3" bs=1048576 status=none | sha256sum | awk '{print $1}')
expect=$(sha256sum "$SUPER_IMG" | awk '{print $1}')
[[ "$readback" == "$expect" ]] || { echo "readback $readback != $expect" >&2; exit 1; }
sync
echo "OK $readback"
