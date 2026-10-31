#!/bin/bash
# The userdata partition sits on the old postmarketOS root. Its first 4 KiB
# still contains an ext4 superblock, so partition_wiped() is false and
# fs_mgr will not format it. Zero the header only. Do not touch super,
# the kernel slot, or the log partition.
set -euo pipefail
DISK=/dev/sdb

[[ $(id -u) -eq 0 ]] || { echo "need root" >&2; exit 1; }
[[ $(findmnt -n -o SOURCE /) != /dev/sdb* ]] || { echo "workstation root is on sdb" >&2; exit 1; }
[[ -b $DISK ]] || { echo "no $DISK" >&2; exit 1; }
readlink -f "/sys/block/sdb/device" | grep -q /usb || { echo "sdb is not USB" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL ${DISK}3) == super ]] || { echo "sdb3 is not super" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL ${DISK}4) == metadata ]] || { echo "sdb4 is not metadata" >&2; exit 1; }
[[ $(blkid -o value -s PARTLABEL ${DISK}6) == userdata ]] || { echo "sdb6 is not userdata" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb6/start) == 17940480 ]] || { echo "sdb6 start changed" >&2; exit 1; }
[[ $(cat /sys/block/sdb/sdb4/start) == 17899520 ]] || { echo "sdb4 start changed" >&2; exit 1; }
findmnt ${DISK}4 >/dev/null 2>&1 && { echo "sdb4 is mounted" >&2; exit 1; }
findmnt ${DISK}6 >/dev/null 2>&1 && { echo "sdb6 is mounted" >&2; exit 1; }

python3 - <<'PY'
def kind(path):
    with open(path, 'rb') as f:
        b = f.read(4096)
    if b == b'\x00' * len(b):
        return 'all-zero'
    if b == b'\xff' * len(b):
        return 'all-ones'
    return 'mixed'
print('before-metadata', kind('/dev/sdb4'))
print('before-userdata', kind('/dev/sdb6'))
PY

# Both partitions overlap the old postmarketOS root, so the first 4 KiB is
# neither all zeros nor all ones. fs_mgr then refuses to format them.
dd if=/dev/zero of=${DISK}4 bs=1048576 count=1 conv=fsync status=none
dd if=/dev/zero of=${DISK}6 bs=1048576 count=1 conv=fsync status=none
python3 - <<'PY'
def wiped(path):
    with open(path, 'rb') as f:
        b = f.read(4096)
    return 'all-zero' if b == b'\x00' * len(b) else 'NOT WIPED'
print('metadata', wiped('/dev/sdb4'))
print('userdata', wiped('/dev/sdb6'))
PY
echo OK
