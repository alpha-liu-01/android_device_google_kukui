#!/bin/bash
# Write the phase 1 depthcharge image to the USB kernel slot only.
# Refuses any disk that holds the running root, and refuses anything
# that is not the USB pmOS_kernel partition at sector 8192.

set -euo pipefail

IMG=/home/alpha/Documents/GitHub/android_device_google_kukui/work/phase1/kernel.kpart
DEV=/dev/sdb1
EXPECT=3ef3953f79e6f36a03b093602d615a2aa1107f158beaa48875d6965ba8237f72

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root" >&2
	exit 1
fi

syspath=$(readlink -f /sys/block/sdb/device)
case "$syspath" in
	*/usb*) ;;
	*) echo "sdb is not a USB disk: $syspath" >&2; exit 1 ;;
esac

grep -qx 'PARTNAME=pmOS_kernel' /sys/class/block/sdb1/uevent
test "$(cat /sys/class/block/sdb1/start)" = 8192
test "$(cat /sys/class/block/sdb1/size)" = 65536

rootdev=$(findmnt -n -o SOURCE /)
case "$rootdev" in
	/dev/sdb* | /dev/nvme*sdb*) echo "refusing: root is $rootdev" >&2; exit 1 ;;
esac

size=$(stat -c %s "$IMG")
max=$((65536 * 512))
test "$size" -le "$max"
test "$size" -gt 1000000
echo "$EXPECT  $IMG" | sha256sum -c -

dd if="$IMG" of="$DEV" bs=4096 conv=fsync status=none
sync
got=$(dd if="$DEV" bs=4096 count=$(((size + 4095) / 4096)) status=none | head -c "$size" | sha256sum | awk '{print $1}')
echo "wrote $size bytes to $DEV, readback $got"
test "$got" = "$EXPECT"
echo OK
