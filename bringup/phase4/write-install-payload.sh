#!/bin/bash
# Copy the installer payloads onto the SanDisk pmOS_boot partition.
# Does not write the kernel slot, super, metadata, misc, or userdata.
set -euo pipefail

PAYLOAD=${1:?need the payload directory}
BYID=/dev/disk/by-id/usb-Generic_MassStorageClass_000000002959-0:0
YMTC=/dev/disk/by-id/usb-NVME_USB_3.2_0123456789ABC-0:0
EXPECT=1ebedee8e582b76f78dd6f3b7468ca3d4a1c5164c222ce11aacf66d7df9ed545
MNT=/mnt/kukui-payload-host

[[ $(id -u) -eq 0 ]] || { echo "need root" >&2; exit 1; }
[[ -f $PAYLOAD/android.kpart && -f $PAYLOAD/menu.kpart && -f $PAYLOAD/linux.kpart.sha256 ]] || {
    echo "payload is incomplete" >&2
    exit 1
}
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
[[ $(blkid -o value -s PARTLABEL ${DISK}2) == pmOS_boot ]] || { echo "p2 is not pmOS_boot" >&2; exit 1; }
[[ $(cat /sys/block/$NAME/${NAME}1/start) == 8192 ]] || { echo "kernel start changed" >&2; exit 1; }
[[ $(cat /sys/block/$NAME/${NAME}1/size) == 65536 ]] || { echo "kernel size changed" >&2; exit 1; }

head_hash() {
    dd if="$1" bs=1048576 count=1 status=none | sha256sum | awk '{print $1}'
}
kern_before=$(head_hash ${DISK}1)
[[ $kern_before == "$EXPECT" ]] || { echo "kernel 1MiB is $kern_before" >&2; exit 1; }

mkdir -p "$MNT"
mount -o rw "${DISK}2" "$MNT"
cleanup() { umount "$MNT" || true; }
trap cleanup EXIT
rm -rf "$MNT/kukui-install"
cp -a "$PAYLOAD" "$MNT/kukui-install"
sync
# The copy must not have touched the kernel slot.
kern_mid=$(head_hash ${DISK}1)
[[ $kern_mid == "$EXPECT" ]] || { echo "kernel slot changed while copying" >&2; exit 1; }
echo "payload on ${DISK}2"
find "$MNT/kukui-install" -type f -printf '%s %p\n' | sort
trap - EXIT
umount "$MNT"
kern_after=$(head_hash ${DISK}1)
[[ $kern_after == "$EXPECT" ]] || { echo "kernel slot changed" >&2; exit 1; }
echo "OK kernel 1MiB unchanged $kern_after"
