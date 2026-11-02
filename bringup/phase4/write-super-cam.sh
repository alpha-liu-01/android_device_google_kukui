#!/bin/bash
# Write one raw super image onto the SanDisk reader only.
# Does not repartition. Does not touch the kernel slot, pmOS_boot,
# metadata, misc, or userdata. Refuses the YMTC build disk.
set -euo pipefail

SUPER_IMG=${1:?need unsparsed super image}
BYID=/dev/disk/by-id/usb-Generic_MassStorageClass_000000002959-0:0
YMTC=/dev/disk/by-id/usb-NVME_USB_3.2_0123456789ABC-0:0

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
udevadm info -q property -n "$DISK" | grep -qx 'ID_SERIAL=Generic_MassStorageClass_000000002959-0:0' || {
    echo "serial does not match the Sandisk reader" >&2
    exit 1
}

for node in $(lsblk -ln -o NAME "$DISK"); do
    findmnt "/dev/$node" >/dev/null 2>&1 && { echo "/dev/$node is mounted" >&2; exit 1; }
done

[[ $(blkid -o value -s PARTLABEL ${DISK}1) == pmOS_kernel ]] || { echo "p1 is not pmOS_kernel" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL ${DISK}3) == super ]] || { echo "p3 is not super" >&2; exit 1; }
[[ $(cat /sys/block/$NAME/${NAME}1/start) == 8192 ]] || { echo "kernel start changed" >&2; exit 1; }
[[ $(cat /sys/block/$NAME/${NAME}1/size) == 65536 ]] || { echo "kernel size changed" >&2; exit 1; }
[[ $(cat /sys/block/$NAME/${NAME}3/start) == 1122304 ]] || { echo "super start changed" >&2; exit 1; }
[[ $(cat /sys/block/$NAME/${NAME}3/size) == 16777216 ]] || { echo "super size changed" >&2; exit 1; }

img_bytes=$(stat -c %s "$SUPER_IMG")
[[ "$img_bytes" -eq 8589934592 ]] || { echo "super image is not 8 GiB" >&2; exit 1; }

head_hash() {
    dd if="$1" bs=1048576 count=1 status=none | sha256sum | awk '{print $1}'
}

kern_before=$(head_hash ${DISK}1)
boot_before=$(head_hash ${DISK}2)
meta_before=$(head_hash ${DISK}4)
misc_before=$(head_hash ${DISK}5)
data_before=$(head_hash ${DISK}6)
echo "target ${DISK}3 serial 000000002959"
echo "kernel 1MiB before $kern_before"

dd if="$SUPER_IMG" of=${DISK}3 bs=1048576 conv=fsync status=progress
sync
echo "readback"
readback=$(dd if=${DISK}3 bs=1048576 status=none | sha256sum | awk '{print $1}')
expect=$(sha256sum "$SUPER_IMG" | awk '{print $1}')
[[ "$readback" == "$expect" ]] || { echo "readback $readback != $expect" >&2; exit 1; }

kern_after=$(head_hash ${DISK}1)
boot_after=$(head_hash ${DISK}2)
meta_after=$(head_hash ${DISK}4)
misc_after=$(head_hash ${DISK}5)
data_after=$(head_hash ${DISK}6)
[[ "$kern_after" == "$kern_before" ]] || { echo "kernel slot changed" >&2; exit 1; }
[[ "$boot_after" == "$boot_before" ]] || { echo "pmOS_boot changed" >&2; exit 1; }
[[ "$meta_after" == "$meta_before" ]] || { echo "metadata changed" >&2; exit 1; }
[[ "$misc_after" == "$misc_before" ]] || { echo "misc changed" >&2; exit 1; }
[[ "$data_after" == "$data_before" ]] || { echo "userdata changed" >&2; exit 1; }

echo "OK super $readback"
echo "kernel 1MiB unchanged $kern_after"
echo "boot $boot_after metadata $meta_after misc $misc_after userdata $data_after"
