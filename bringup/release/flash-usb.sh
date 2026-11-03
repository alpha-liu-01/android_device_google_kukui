#!/bin/bash
# Write a Kukui installer disk. The disk is wiped.
#   flash-usb.sh --confirm sdb /dev/sdb /path/to/images
# --confirm must be the disk's basename. There is no default disk.
set -euo pipefail

CONFIRM=""
if [[ "${1:-}" == "--confirm" ]]; then
    CONFIRM="${2:?need the disk basename after --confirm}"
    shift 2
fi
DISK="${1:?need the whole-disk path, for example /dev/sdb}"
IMAGES="${2:-$(cd "$(dirname "$0")" && pwd)/images}"
SGDISK="${SGDISK:-sgdisk}"
MAKE_F2FS="${MAKE_F2FS:-make_f2fs}"
ATTR=0x01ff000000000000
SUPER_BYTES=8589934592

[[ "$(id -u)" -eq 0 ]] || { echo "need root" >&2; exit 1; }
[[ -b "$DISK" ]] || { echo "$DISK is not a block device" >&2; exit 1; }
DISK="$(readlink -f "$DISK")"
NAME="${DISK#/dev/}"
[[ "$NAME" != *"/"* ]] || { echo "could not name $DISK" >&2; exit 1; }

# 1. Whole disk, not a partition node.
[[ "$(lsblk -no TYPE "$DISK" | head -n 1)" == "disk" ]] || {
    echo "$DISK is not a whole disk" >&2
    exit 1
}

# 2. Not the workstation root, home disk, or an nvme node.
root_src="$(findmnt -no SOURCE /)"
root_disk="$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -n 1)"
[[ -n "$root_disk" ]] || root_disk="${root_src#/dev/}"
[[ "$NAME" != "$root_disk" ]] || { echo "$DISK holds /" >&2; exit 1; }
if [[ -n "${HOME:-}" ]]; then
    home_src="$(findmnt -no SOURCE "$HOME" 2>/dev/null || df -P "$HOME" | awk 'NR==2 {print $1}')"
    home_disk="$(lsblk -no PKNAME "$home_src" 2>/dev/null | head -n 1 || true)"
    [[ -n "$home_disk" ]] || home_disk="${home_src#/dev/}"
    home_disk="${home_disk%%[0-9]*}"
    [[ "$NAME" != "$home_disk" && "$NAME" != "${home_src#/dev/}" ]] || {
        echo "$DISK holds the home directory" >&2
        exit 1
    }
fi
[[ "$NAME" != nvme* && "$DISK" != *nvme* ]] || { echo "$DISK is nvme" >&2; exit 1; }

# 3. The workstation YMTC disk, by serial or model.
props="$(udevadm info -q property -n "$DISK")"
ID_SERIAL="$(printf '%s\n' "$props" | sed -n 's/^ID_SERIAL=//p' | head -n 1)"
ID_MODEL="$(printf '%s\n' "$props" | sed -n 's/^ID_MODEL=//p' | head -n 1)"
ID_BUS="$(printf '%s\n' "$props" | sed -n 's/^ID_BUS=//p' | head -n 1)"
case "${ID_SERIAL:-} ${ID_MODEL:-}" in
    *0123456789ABC*|*YMTC*|*NVME_USB*)
        echo "$DISK looks like the YMTC disk (${ID_SERIAL:-} ${ID_MODEL:-})" >&2
        exit 1
        ;;
esac

# 4. USB in sysfs.
readlink -f "/sys/block/$NAME/device" | grep -q '/usb' || {
    echo "$DISK is not USB" >&2
    exit 1
}

# 5. Nothing on it is mounted.
if lsblk -ln -o MOUNTPOINT "$DISK" | grep -q .; then
    echo "$DISK has a mounted partition" >&2
    lsblk -o NAME,SIZE,MOUNTPOINT "$DISK" >&2
    exit 1
fi

# 6. Large enough for the 8 GiB super and a data partition, not a huge internal disk.
sectors="$(cat "/sys/block/$NAME/size")"
min_sectors=$((32 * 1024 * 1024 * 1024 / 512))
max_sectors=$((256 * 1024 * 1024 * 1024 / 512))
[[ "$sectors" -ge "$min_sectors" && "$sectors" -le "$max_sectors" ]] || {
    echo "$DISK has $sectors sectors, want between $min_sectors and $max_sectors" >&2
    exit 1
}

[[ -f "$IMAGES/MANIFEST" ]] || { echo "no MANIFEST in $IMAGES" >&2; exit 1; }
manifest_field() {
    awk -v name="$1" '$1 == name { print $2, $3 }' "$IMAGES/MANIFEST"
}
check_file() {
    local name="$1"
    local size hash got_size got_hash
    read -r size hash <<<"$(manifest_field "$name")"
    [[ -n "$size" && -n "$hash" ]] || { echo "MANIFEST missing $name" >&2; exit 1; }
    [[ -f "$IMAGES/$name" ]] || { echo "missing $IMAGES/$name" >&2; exit 1; }
    got_size="$(stat -c %s "$IMAGES/$name")"
    got_hash="$(sha256sum "$IMAGES/$name" | awk '{print $1}')"
    [[ "$got_size" == "$size" && "$got_hash" == "$hash" ]] || {
        echo "$name does not match MANIFEST ($got_size $got_hash)" >&2
        exit 1
    }
}
check_file kernel.kpart
check_file android.kpart
check_file menu.kpart
check_file super.img
grep -qx 'cmdline kernel.kpart androidboot.boot_devices=soc/11201000.usb/11200000.usb' "$IMAGES/MANIFEST"
grep -qx 'cmdline android.kpart androidboot.boot_devices=soc/11230000.mmc' "$IMAGES/MANIFEST"
super_size="$(awk '$1=="super.img" {print $2}' "$IMAGES/MANIFEST")"
[[ "$super_size" -eq "$SUPER_BYTES" ]] || { echo "super.img size is not 8 GiB" >&2; exit 1; }
usb_cfg="$(futility dump_kernel_config "$IMAGES/kernel.kpart")"
emmc_cfg="$(futility dump_kernel_config "$IMAGES/android.kpart")"
grep -q -F 'androidboot.boot_devices=soc/11201000.usb/11200000.usb' <<<"$usb_cfg"
grep -q -F 'androidboot.boot_devices=soc/11230000.mmc' <<<"$emmc_cfg"
grep -q 'console=ttynull' <<<"$(futility dump_kernel_config "$IMAGES/menu.kpart")"

gib=$((sectors * 512 / 1024 / 1024 / 1024))
echo "target $DISK"
echo "model ${ID_MODEL:-unknown}"
echo "serial ${ID_SERIAL:-unknown}"
echo "size ${gib} GiB ($sectors sectors)"
echo "bus ${ID_BUS:-unknown}"
if [[ "$CONFIRM" != "$NAME" ]]; then
    echo "refusing to write. Re-run with --confirm $NAME after checking the lines above." >&2
    exit 1
fi

command -v "$SGDISK" >/dev/null || { echo "sgdisk not found" >&2; exit 1; }
command -v "$MAKE_F2FS" >/dev/null || { echo "make_f2fs not found" >&2; exit 1; }

part() {
    if [[ "$NAME" =~ [0-9]$ ]]; then
        echo "/dev/${NAME}p$1"
    else
        echo "/dev/${NAME}$1"
    fi
}

echo "wiping partition table"
"$SGDISK" --zap-all "$DISK"
"$SGDISK" \
    --new=1:8192:73727 --change-name=1:pmOS_kernel --typecode=1:FE3A2A5D-4F32-41A7-B725-ACCC3285A309 \
    --new=2:73728:1122303 --change-name=2:pmOS_boot --typecode=2:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new=3:1122304:17899519 --change-name=3:super --typecode=3:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new=4:17899520:17932287 --change-name=4:metadata --typecode=4:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new=5:17932288:17940479 --change-name=5:misc --typecode=5:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new=6:17940480:0 --change-name=6:userdata --typecode=6:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    "$DISK"
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
if header[0:8] != b"EFI PART":
    sys.exit("primary GPT header missing")
entry_lba, entry_size = struct.unpack_from("<QI", header, 72)
with open(path, "rb") as f:
    f.seek(entry_lba * 512)
    entry = f.read(entry_size)
got = struct.unpack_from("<Q", entry, 48)[0]
print(f"kernel attributes {got:#018x}")
if got != want:
    sys.exit("kernel attributes are not priority 15, tries 15, successful 1")
PY

partprobe "$DISK" 2>/dev/null || blockdev --rereadpt "$DISK"
udevadm settle
for n in 1 2 3 4 5 6; do
    [[ -b "$(part "$n")" ]] || { echo "missing partition $n" >&2; exit 1; }
done
[[ "$(cat "/sys/class/block/${NAME}1/start")" == 8192 ]]
[[ "$(cat "/sys/class/block/${NAME}3/start")" == 1122304 ]]
[[ "$(cat "/sys/class/block/${NAME}3/size")" == 16777216 ]]

hash_prefix() {
    local node="$1"
    local bytes="$2"
    local blocks=$((bytes / 4096))
    [[ $((bytes % 4096)) -eq 0 ]] || { echo "$node image length is not a 4096 multiple" >&2; exit 1; }
    dd if="$node" bs=4096 count="$blocks" status=none | sha256sum | awk '{print $1}'
}

echo "writing kernel"
dd if="$IMAGES/kernel.kpart" of="$(part 1)" bs=1048576 conv=fsync status=none
kern_bytes="$(stat -c %s "$IMAGES/kernel.kpart")"
kern_hash="$(hash_prefix "$(part 1)" "$kern_bytes")"
want="$(awk '$1=="kernel.kpart"{print $3}' "$IMAGES/MANIFEST")"
[[ "$kern_hash" == "$want" ]] || { echo "kernel readback $kern_hash" >&2; exit 1; }
echo "kernel $kern_hash"

echo "writing super"
dd if="$IMAGES/super.img" of="$(part 3)" bs=1048576 conv=fsync status=progress
super_hash="$(hash_prefix "$(part 3)" "$SUPER_BYTES")"
want="$(awk '$1=="super.img"{print $3}' "$IMAGES/MANIFEST")"
[[ "$super_hash" == "$want" ]] || { echo "super readback $super_hash" >&2; exit 1; }
echo "super $super_hash"

echo "formatting boot, metadata, userdata"
mkfs.ext4 -F -L pmOS_boot -E lazy_itable_init=0,lazy_journal_init=0 "$(part 2)"
mkfs.ext4 -F -L metadata -E lazy_itable_init=0,lazy_journal_init=0 "$(part 4)"
dd if=/dev/zero of="$(part 5)" bs=1048576 count=4 conv=fsync status=none
"$MAKE_F2FS" -f -O encrypt,extra_attr,project_quota,quota,compression -l userdata "$(part 6)"

mnt="$(mktemp -d)"
mount -t ext4 "$(part 2)" "$mnt"
mkdir -p "$mnt/kukui-install"
cp -a "$IMAGES/android.kpart" "$IMAGES/menu.kpart" "$mnt/kukui-install/"
umount "$mnt"
sync
mount -t ext4 -o ro "$(part 2)" "$mnt"
android_hash="$(sha256sum "$mnt/kukui-install/android.kpart" | awk '{print $1}')"
menu_hash="$(sha256sum "$mnt/kukui-install/menu.kpart" | awk '{print $1}')"
umount "$mnt"
rmdir "$mnt"
want_android="$(awk '$1=="android.kpart"{print $3}' "$IMAGES/MANIFEST")"
want_menu="$(awk '$1=="menu.kpart"{print $3}' "$IMAGES/MANIFEST")"
[[ "$android_hash" == "$want_android" ]] || { echo "android.kpart readback $android_hash" >&2; exit 1; }
[[ "$menu_hash" == "$want_menu" ]] || { echo "menu.kpart readback $menu_hash" >&2; exit 1; }
echo "android.kpart $android_hash"
echo "menu.kpart $menu_hash"

sync
echo "OK $DISK"
