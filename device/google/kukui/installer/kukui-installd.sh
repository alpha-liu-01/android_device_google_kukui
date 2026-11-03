#!/system/bin/sh
# Install the running USB Android onto the Krane eMMC.
# The USB kernel slot is never written. Nothing happens until a request
# file contains confirm=yes.
set -u

PAYLOAD=""
STATUS_DIR=""
DISK_SECTORS=0

log() {
    echo "$1"
    if [ -n "$STATUS_DIR" ]; then
        printf '%s\n' "$1" >> "$STATUS_DIR/log"
        chmod 644 "$STATUS_DIR/log" 2>/dev/null || true
    fi
}

write_status() {
    local tmp="$STATUS_DIR/status.tmp"
    printf '%s\n' "$@" > "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "$STATUS_DIR/status"
    chmod 644 "$STATUS_DIR/status"
    log "status $(printf '%s | ' "$@")"
}

fail() {
    # $1 is an English code. The app maps it to a translated string.
    # Further arguments are extra status lines, key=value.
    local code="$1"
    shift
    log "failed: $code"
    write_status "state=failed" "code=$code" "$@"
    exit 0
}

disk_of() {
    local n="$1"
    local path
    while [ -e "/sys/class/block/$n/partition" ]; do
        path=$(readlink -f "/sys/class/block/$n")
        n=$(basename "$(dirname "$path")")
    done
    printf '%s\n' "$n"
}

sysfs_of() {
    readlink -f "/sys/class/block/$1/device" 2>/dev/null || true
}

boot_disk() {
    local dev base
    dev=$(readlink -f /dev/block/by-name/super 2>/dev/null || true)
    if [ -z "$dev" ]; then
        return 1
    fi
    base=$(basename "$dev")
    if [ -d "/sys/class/block/$base/slaves" ]; then
        base=$(ls "/sys/class/block/$base/slaves" 2>/dev/null | head -n 1)
        [ -n "$base" ] || return 1
    fi
    disk_of "$base"
}

require_identity() {
    local boot path rem target_path
    boot=$(boot_disk) || fail no_boot_super
    path=$(sysfs_of "$boot")
    case "$path" in
        *11201000.usb*|*11200000.usb*) ;;
        *) fail boot_not_usb "boot=$boot" "path=$path" ;;
    esac
    [ -e /sys/class/block/mmcblk0 ] || fail no_mmcblk0
    target_path=$(sysfs_of mmcblk0)
    case "$target_path" in
        *11230000.mmc*) ;;
        *) fail mmc_not_emmc "path=$target_path" ;;
    esac
    case "$target_path" in
        *11201000.usb*|*11200000.usb*) fail target_has_usb ;;
    esac
    rem=$(cat /sys/class/block/mmcblk0/removable 2>/dev/null || echo missing)
    [ "$rem" = 0 ] || fail mmc_removable "removable=$rem"
    [ "$boot" != mmcblk0 ] || fail same_disk
    BOOT_DISK=$boot
    TARGET_PATH=$target_path
    log "boot $BOOT_DISK $path"
    log "target mmcblk0 $target_path"
}

mount_payload() {
    local part name uevent
    PAYLOAD=/mnt/kukui-payload
    mkdir -p "$PAYLOAD"
    if grep -q " $PAYLOAD " /proc/mounts 2>/dev/null; then
        return 0
    fi
    for part in /sys/class/block/${BOOT_DISK}*; do
        name=$(basename "$part")
        [ "$name" = "$BOOT_DISK" ] && continue
        uevent=$(cat "/sys/class/block/$name/uevent" 2>/dev/null || true)
        case "$uevent" in
            *PARTNAME=pmOS_boot*)
                mount -t ext4 -o rw "/dev/block/$name" "$PAYLOAD" || \
                    mount -t ext4 "/dev/block/$name" "$PAYLOAD" || \
                    fail mount_pmos_boot_failed
                return 0
                ;;
        esac
    done
    fail no_pmos_boot
}

read_tune() {
    local line key val
    BLOCK_COUNT=0
    FREE_BLOCKS=0
    BLOCK_SIZE=0
    tune2fs -l /dev/block/mmcblk0p3 | while read -r line; do
        printf '%s\n' "$line"
    done > /mnt/kukui-tune.txt
    while read -r line; do
        key=${line%%:*}
        val=${line#*:}
        val=${val# }
        case "$key" in
            "Block count") BLOCK_COUNT=$val ;;
            "Free blocks") FREE_BLOCKS=$val ;;
            "Block size") BLOCK_SIZE=$val ;;
        esac
    done < /mnt/kukui-tune.txt
    [ "$BLOCK_COUNT" -gt 0 ] && [ "$BLOCK_SIZE" -gt 0 ] || fail no_ext4_blocks
}

# toybox sh on this device evaluates $(( )) in 32-bit signed arithmetic.
# 16 * 1024 * 1024 * 1024 wraps to 0. Keep every product under 2^31.
plan_dual() {
    local used_blocks per_mib used_mib need_mib min_gib disk overhead room max_gib gib
    local free_after data_sectors
    read_tune
    per_mib=$((1048576 / BLOCK_SIZE))
    [ "$per_mib" -gt 0 ] || fail bad_block_size
    used_blocks=$((BLOCK_COUNT - FREE_BLOCKS))
    used_mib=$((used_blocks / per_mib))
    need_mib=$((used_mib + 2048))
    min_gib=$(((need_mib + 1023) / 1024))
    [ "$min_gib" -ge 1 ] || min_gib=1
    disk=$(cat /sys/class/block/mmcblk0/size)
    DISK_SECTORS=$disk
    overhead=$((65536 + 65536 + 131072 + 16777216 + 32768 + 8192))
    # Root sectors left after the fixed layout and 8 GiB of userdata.
    room=$((disk - 1122304 - 64 - overhead - 16777216))
    if [ "$room" -lt 2097152 ]; then
        fail not_enough_room
    fi
    max_gib=$((room / 2097152))
    if [ "$min_gib" -gt "$max_gib" ]; then
        fail not_enough_room
    fi
    MIN_GIB=$min_gib
    MAX_GIB=$max_gib
    if [ -n "${REQUEST_GIB:-}" ]; then
        case "$REQUEST_GIB" in
            *[!0-9]*) fail gib_not_integer ;;
        esac
        if [ "${#REQUEST_GIB}" -gt 4 ]; then
            fail gib_out_of_range "min_gib=$MIN_GIB" "max_gib=$MAX_GIB"
        fi
        gib=$(printf '%s' "$REQUEST_GIB" | sed 's/^0*//')
        [ -n "$gib" ] || gib=0
        gib=$((gib + 0))
        if [ "$gib" -lt "$MIN_GIB" ] || [ "$gib" -gt "$MAX_GIB" ]; then
            fail gib_out_of_range "min_gib=$MIN_GIB" "max_gib=$MAX_GIB"
        fi
    else
        gib=16
        if [ "$gib" -lt "$MIN_GIB" ]; then
            gib=$MIN_GIB
        fi
        if [ "$gib" -gt "$MAX_GIB" ]; then
            gib=$MAX_GIB
        fi
    fi
    ROOT_GIB=$gib
    ROOT_SECTORS=$((gib * 2048 * 1024))
    free_after=$((disk - 1122304 - ROOT_SECTORS - 64))
    data_sectors=$((free_after - overhead))
    if [ "$data_sectors" -lt 16777216 ]; then
        fail not_enough_room
    fi
    DATA_GIB=$((data_sectors / 2097152))
    DATA_SECTORS=$data_sectors
}

plan_android() {
    local disk data_sectors
    disk=$(cat /sys/class/block/mmcblk0/size)
    DISK_SECTORS=$disk
    data_sectors=$((disk - 17940480 - 64))
    [ "$data_sectors" -gt 16777216 ] || fail emmc_too_small
    DATA_GIB=$((data_sectors / 2097152))
    DATA_SECTORS=$data_sectors
    ROOT_GIB=0
}

set_kernel_attr_full() {
    local part="$1"
    sgdisk \
        --attributes="$part":set:48 --attributes="$part":set:49 \
        --attributes="$part":set:50 --attributes="$part":set:51 \
        --attributes="$part":set:52 --attributes="$part":set:53 \
        --attributes="$part":set:54 --attributes="$part":set:55 \
        --attributes="$part":set:56 \
        /dev/block/mmcblk0 || fail attr_failed "part=$part"
}

set_kernel_attr_low() {
    local part="$1"
    # priority 1, tries 5, successful 1. Clear the bits a previous
    # priority-15 slot still has set.
    sgdisk \
        --attributes="$part":clear:49 --attributes="$part":clear:50 \
        --attributes="$part":clear:51 --attributes="$part":clear:53 \
        --attributes="$part":clear:55 \
        --attributes="$part":set:48 \
        --attributes="$part":set:52 --attributes="$part":set:54 \
        --attributes="$part":set:56 \
        /dev/block/mmcblk0 || fail attr_failed "part=$part"
}

part_name() {
    sed -n 's/^PARTNAME=//p' "/sys/class/block/$1/uevent" | head -n 1
}

part_by_name() {
    local want="$1" part base got
    for part in /sys/class/block/mmcblk0p*; do
        [ -e "$part" ] || continue
        base=$(basename "$part")
        got=$(part_name "$base")
        if [ "$got" = "$want" ]; then
            printf '%s\n' "$base"
            return 0
        fi
    done
    return 1
}

attr_flags() {
    local n=${1#mmcblk0p}
    sgdisk --info="$n" /dev/block/mmcblk0 | sed -n 's/^Attribute flags: //p' | head -n 1
}

expect_part() {
    local got
    got=$(part_name "$1")
    [ "$got" = "$2" ] || fail part_name_mismatch "part=$1" "got=${got:-empty}" "want=$2"
}

super_source() {
    local src base path dest_disk
    src=$(readlink -f /dev/block/by-name/super)
    base=$(basename "$src")
    if [ -d "/sys/class/block/$base/slaves" ]; then
        base=$(ls "/sys/class/block/$base/slaves" 2>/dev/null | head -n 1)
        [ -n "$base" ] || fail super_no_slave
    fi
    base=$(disk_of "$base")
    path=$(sysfs_of "$base")
    case "$path" in
        *11201000.usb*|*11200000.usb*) ;;
        *) fail super_not_usb "disk=$base" "path=$path" ;;
    esac
    dest_disk=$(disk_of "$(basename "$(readlink -f "$1")")")
    [ "$dest_disk" != "$base" ] || fail super_same_disk
    printf '%s\n' "$src"
}

reread() {
    blockdev --rereadpt /dev/block/mmcblk0 || true
    sleep 2
}

backup_kernel() {
    mkdir -p "$PAYLOAD/kukui-install/backup"
    if [ -f "$PAYLOAD/kukui-install/backup/mmcblk0.gpt" ] && \
        [ -f "$PAYLOAD/kukui-install/backup/mmcblk0p1.kpart" ]; then
        log "keeping existing kernel and gpt backup"
        return 0
    fi
    log "backing up mmcblk0p1 and gpt"
    dd if=/dev/block/mmcblk0p1 of="$PAYLOAD/kukui-install/backup/mmcblk0p1.kpart" bs=1048576 conv=fsync || \
        fail backup_kernel_failed
    sgdisk --backup="$PAYLOAD/kukui-install/backup/mmcblk0.gpt" /dev/block/mmcblk0 || \
        fail backup_gpt_failed
    sync
}

refuse_mounted_emmc() {
    if grep -q mmcblk0 /proc/mounts 2>/dev/null; then
        fail emmc_mounted
    fi
}

set_kernel_attr_off() {
    local part="$1" bit
    # Priority 0 and tries 0 until the final commit. A half-written
    # kernel slot must not become what Ctrl+D boots.
    for bit in 48 49 50 51 52 53 54 55 56; do
        sgdisk --attributes="$part":clear:"$bit" /dev/block/mmcblk0 || \
            fail clear_attr_failed "part=$part"
    done
}

check_payload() {
    [ -f "$PAYLOAD/kukui-install/android.kpart" ] || fail missing_android_kpart
    [ -f "$PAYLOAD/kukui-install/android/Image" ] || fail missing_android_image
    [ -f "$PAYLOAD/kukui-install/android/cmdline" ] || fail missing_android_cmdline
}

hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

hash_part() {
    local dev="$1" bytes="$2" mib
    # bytes stays under 32 MiB here. The 8 GiB super uses hash_super.
    mib=$(((bytes + 1048575) / 1048576))
    dd if="$dev" bs=1048576 count="$mib" status=none | \
        head -c "$bytes" | sha256sum | awk '{print $1}'
}

hash_super() {
    dd if="$1" bs=1048576 count=8192 status=none | sha256sum | awk '{print $1}'
}

install_android_only() {
    local src_hash got
    check_payload
    plan_android
    refuse_mounted_emmc
    write_status "state=running" "percent=5" "code=backing_up_kernel"
    backup_kernel
    write_status "state=running" "percent=15" "code=writing_gpt"
    sgdisk --zap-all /dev/block/mmcblk0 || fail zap_failed
    # This sgdisk rejects -a. Explicit sector numbers are already 1 MiB aligned.
    sgdisk \
        --new=1:8192:73727 --change-name=1:pmOS_kernel --typecode=1:FE3A2A5D-4F32-41A7-B725-ACCC3285A309 \
        --new=2:73728:1122303 --change-name=2:pmOS_boot --typecode=2:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
        --new=3:1122304:17899519 --change-name=3:super --typecode=3:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
        --new=4:17899520:17932287 --change-name=4:metadata --typecode=4:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
        --new=5:17932288:17940479 --change-name=5:misc --typecode=5:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
        --new=6:17940480:0 --change-name=6:userdata --typecode=6:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
        /dev/block/mmcblk0 || fail android_partition_failed
    reread
    expect_part mmcblk0p1 pmOS_kernel
    expect_part mmcblk0p3 super
    expect_part mmcblk0p4 metadata
    expect_part mmcblk0p6 userdata
    write_status "state=running" "percent=30" "code=writing_android_kernel"
    dd if="$PAYLOAD/kukui-install/android.kpart" of=/dev/block/mmcblk0p1 bs=1048576 conv=fsync || \
        fail write_kernel_failed
    src_hash=$(hash_file "$PAYLOAD/kukui-install/android.kpart")
    got=$(hash_part /dev/block/mmcblk0p1 "$(stat -c %s "$PAYLOAD/kukui-install/android.kpart")")
    [ "$src_hash" = "$got" ] || fail kernel_hash_mismatch
    write_status "state=running" "percent=45" "code=copying_super"
    dd if="$(super_source /dev/block/mmcblk0p3)" of=/dev/block/mmcblk0p3 bs=1048576 conv=fsync || fail copy_super_failed
    got=$(hash_super /dev/block/mmcblk0p3)
    src_hash=$(hash_super /dev/block/by-name/super)
    [ "$src_hash" = "$got" ] || fail super_hash_mismatch
    write_status "state=running" "percent=85" "code=formatting_data"
    mke2fs -t ext4 -F -L metadata /dev/block/mmcblk0p4 || fail format_metadata_failed
    dd if=/dev/zero of=/dev/block/mmcblk0p5 bs=1048576 count=4 conv=fsync status=none || true
    make_f2fs -f -g android -O encrypt,extra_attr,project_quota,quota,compression /dev/block/mmcblk0p6 || \
        fail format_userdata_failed
    set_kernel_attr_full 1
    sync
    write_status "state=ready_reboot" "percent=100" "code=ready_android"
}

install_dual() {
    local end src_hash got expect live fit_bytes ec current args n
    local menu_start menu_end android_start android_end menu_files_start menu_files_end
    local super_start super_end meta_start meta_end misc_start misc_end data_start
    check_payload
    [ -f "$PAYLOAD/kukui-install/menu.kpart" ] || fail missing_menu
    [ -f "$PAYLOAD/kukui-install/linux/Image" ] || fail missing_linux_image
    [ -f "$PAYLOAD/kukui-install/linux.kpart.sha256" ] || fail missing_linux_hash
    [ -f "$PAYLOAD/kukui-install/linux/kernel.bytes" ] || fail missing_linux_bytes
    plan_dual
    expect=$(tr -d ' \n' < "$PAYLOAD/kukui-install/linux.kpart.sha256")
    fit_bytes=$(tr -d ' \n' < "$PAYLOAD/kukui-install/linux/kernel.bytes")
    live=$(hash_part /dev/block/mmcblk0p1 "$fit_bytes")
    [ "$live" = "$expect" ] || fail linux_kernel_mismatch
    refuse_mounted_emmc
    write_status "state=running" "percent=5" "code=backing_up_kernel"
    backup_kernel
    write_status "state=running" "percent=15" "code=checking_linux_root"
    e2fsck -f -y /dev/block/mmcblk0p3
    ec=$?
    [ "$ec" -le 2 ] || fail e2fsck_failed "exit_code=$ec"
    current=$(cat /sys/class/block/mmcblk0p3/size)
    end=$((1122304 + ROOT_SECTORS - 1))
    menu_start=$((end + 1))
    menu_end=$((menu_start + 65536 - 1))
    android_start=$((menu_end + 1))
    android_end=$((android_start + 65536 - 1))
    menu_files_start=$((android_end + 1))
    menu_files_end=$((menu_files_start + 131072 - 1))
    super_start=$((menu_files_end + 1))
    super_end=$((super_start + 16777216 - 1))
    meta_start=$((super_end + 1))
    meta_end=$((meta_start + 32768 - 1))
    misc_start=$((meta_end + 1))
    misc_end=$((misc_start + 8192 - 1))
    data_start=$((misc_end + 1))
    if [ "$current" -gt "$ROOT_SECTORS" ]; then
        write_status "state=running" "percent=30" "code=shrinking_linux_root"
        resize2fs /dev/block/mmcblk0p3 "${ROOT_GIB}G" || fail resize2fs_failed
    elif [ "$current" -lt "$ROOT_SECTORS" ]; then
        log "root is smaller than requested; grow it after the partition change"
    else
        log "root is already ${ROOT_GIB} GiB"
    fi
    if [ "$(part_name mmcblk0p3)" = pmOS_root ] && \
        [ "$(cat /sys/class/block/mmcblk0p3/start)" = 1122304 ] && \
        [ "$(cat /sys/class/block/mmcblk0p3/size)" = "$ROOT_SECTORS" ] && \
        [ "$(part_name mmcblk0p4)" = menu_kernel ] && \
        [ "$(cat /sys/class/block/mmcblk0p4/start)" = "$menu_start" ] && \
        [ "$(part_name mmcblk0p5)" = android_kernel ] && \
        [ "$(cat /sys/class/block/mmcblk0p5/start)" = "$android_start" ] && \
        [ "$(part_name mmcblk0p6)" = bootmenu ] && \
        [ "$(cat /sys/class/block/mmcblk0p6/start)" = "$menu_files_start" ] && \
        [ "$(part_name mmcblk0p7)" = super ] && \
        [ "$(cat /sys/class/block/mmcblk0p7/start)" = "$super_start" ] && \
        [ "$(part_name mmcblk0p8)" = metadata ] && \
        [ "$(cat /sys/class/block/mmcblk0p8/start)" = "$meta_start" ] && \
        [ "$(part_name mmcblk0p9)" = misc ] && \
        [ "$(cat /sys/class/block/mmcblk0p9/start)" = "$misc_start" ] && \
        [ "$(part_name mmcblk0p10)" = userdata ] && \
        [ "$(cat /sys/class/block/mmcblk0p10/start)" = "$data_start" ]; then
        log "partition table already matches; leaving it"
    else
        args=""
        n=10
        while [ "$n" -ge 4 ]; do
            if [ -e "/sys/class/block/mmcblk0p$n" ]; then
                args="$args --delete=$n"
            fi
            n=$((n - 1))
        done
        if [ "$current" -ne "$ROOT_SECTORS" ]; then
            args="$args --delete=3 --new=3:1122304:$end --change-name=3:pmOS_root --typecode=3:0FC63DAF-8483-4772-8E79-3D69D8477DE4"
        fi
        args="$args --new=4:$menu_start:$menu_end --change-name=4:menu_kernel --typecode=4:FE3A2A5D-4F32-41A7-B725-ACCC3285A309"
        args="$args --new=5:$android_start:$android_end --change-name=5:android_kernel --typecode=5:FE3A2A5D-4F32-41A7-B725-ACCC3285A309"
        args="$args --new=6:$menu_files_start:$menu_files_end --change-name=6:bootmenu --typecode=6:0FC63DAF-8483-4772-8E79-3D69D8477DE4"
        args="$args --new=7:$super_start:$super_end --change-name=7:super --typecode=7:0FC63DAF-8483-4772-8E79-3D69D8477DE4"
        args="$args --new=8:$meta_start:$meta_end --change-name=8:metadata --typecode=8:0FC63DAF-8483-4772-8E79-3D69D8477DE4"
        args="$args --new=9:$misc_start:$misc_end --change-name=9:misc --typecode=9:0FC63DAF-8483-4772-8E79-3D69D8477DE4"
        args="$args --new=10:$data_start:0 --change-name=10:userdata --typecode=10:0FC63DAF-8483-4772-8E79-3D69D8477DE4"
        write_status "state=running" "percent=40" "code=adjusting_gpt"
        # shellcheck disable=SC2086
        sgdisk $args /dev/block/mmcblk0 > "$STATUS_DIR/sgdisk.txt" 2>&1
        ec=$?
        log "sgdisk $(tr '\n' ' ' < "$STATUS_DIR/sgdisk.txt")"
        [ "$ec" -eq 0 ] || fail dual_partition_failed
        reread
        if [ "$current" -lt "$ROOT_SECTORS" ]; then
            resize2fs /dev/block/mmcblk0p3 "${ROOT_GIB}G" || fail grow_root_failed
        fi
    fi
    expect_part mmcblk0p1 pmOS_kernel
    expect_part mmcblk0p3 pmOS_root
    expect_part mmcblk0p4 menu_kernel
    expect_part mmcblk0p5 android_kernel
    expect_part mmcblk0p6 bootmenu
    expect_part mmcblk0p7 super
    expect_part mmcblk0p10 userdata
    set_kernel_attr_off 4
    set_kernel_attr_off 5
    write_status "state=running" "percent=55" "code=writing_kernel_slots"
    dd if="$PAYLOAD/kukui-install/menu.kpart" of=/dev/block/mmcblk0p4 bs=1048576 conv=fsync || fail write_menu_failed
    dd if="$PAYLOAD/kukui-install/android.kpart" of=/dev/block/mmcblk0p5 bs=1048576 conv=fsync || fail write_android_kernel_failed
    src_hash=$(hash_file "$PAYLOAD/kukui-install/menu.kpart")
    got=$(hash_part /dev/block/mmcblk0p4 "$(stat -c %s "$PAYLOAD/kukui-install/menu.kpart")")
    [ "$src_hash" = "$got" ] || fail menu_hash_mismatch
    src_hash=$(hash_file "$PAYLOAD/kukui-install/android.kpart")
    got=$(hash_part /dev/block/mmcblk0p5 "$(stat -c %s "$PAYLOAD/kukui-install/android.kpart")")
    [ "$src_hash" = "$got" ] || fail android_kernel_hash_mismatch
    write_status "state=running" "percent=65" "code=writing_menu_files"
    mke2fs -t ext4 -F -L bootmenu /dev/block/mmcblk0p6 || fail format_bootmenu_failed
    mkdir -p /mnt/kukui-bootmenu
    mount -t ext4 /dev/block/mmcblk0p6 /mnt/kukui-bootmenu || fail mount_bootmenu_failed
    mkdir -p /mnt/kukui-bootmenu/android /mnt/kukui-bootmenu/linux
    cp "$PAYLOAD/kukui-install/android/Image" /mnt/kukui-bootmenu/android/Image
    cp "$PAYLOAD/kukui-install/android/cmdline" /mnt/kukui-bootmenu/android/cmdline
    cp "$PAYLOAD/kukui-install/linux/Image" /mnt/kukui-bootmenu/linux/Image
    cp "$PAYLOAD/kukui-install/linux/cmdline" /mnt/kukui-bootmenu/linux/cmdline
    sync
    umount /mnt/kukui-bootmenu
    # The menu partition is full once both Images are on it. Android's
    # initrd goes on the Linux boot partition, next to the initramfs
    # that is already there.
    [ -f "$PAYLOAD/kukui-install/android/initrd" ] || fail missing_initrd
    expect_part mmcblk0p2 pmOS_boot
    mkdir -p /mnt/kukui-pmosboot
    mount -t ext4 -o rw /dev/block/mmcblk0p2 /mnt/kukui-pmosboot || fail mount_linux_boot_failed
    cp "$PAYLOAD/kukui-install/android/initrd" /mnt/kukui-pmosboot/kukui-android.initrd
    sync
    umount /mnt/kukui-pmosboot
    write_status "state=running" "percent=75" "code=copying_super"
    dd if="$(super_source /dev/block/mmcblk0p7)" of=/dev/block/mmcblk0p7 bs=1048576 conv=fsync || fail copy_super_failed
    got=$(hash_super /dev/block/mmcblk0p7)
    src_hash=$(hash_super /dev/block/by-name/super)
    [ "$src_hash" = "$got" ] || fail super_hash_mismatch
    write_status "state=running" "percent=90" "code=formatting_data"
    mke2fs -t ext4 -F -L metadata /dev/block/mmcblk0p8 || fail format_metadata_failed
    dd if=/dev/zero of=/dev/block/mmcblk0p9 bs=1048576 count=4 conv=fsync status=none || true
    make_f2fs -f -g android -O encrypt,extra_attr,project_quota,quota,compression /dev/block/mmcblk0p10 || \
        fail format_userdata_failed
    write_status "state=running" "percent=96" "code=switching_boot"
    set_kernel_attr_full 4
    set_kernel_attr_low 1
    set_kernel_attr_low 5
    sync
    write_status "state=ready_reboot" "percent=100" "code=ready_dual"
}

require_update_layout() {
    local bytes need fstype
    [ -f "$PAYLOAD/kukui-install/android.kpart" ] || fail missing_android_kpart
    [ -f "$PAYLOAD/kukui-install/menu.kpart" ] || fail missing_menu
    grep -a -q 'androidboot.boot_devices=soc/11230000.mmc' \
        "$PAYLOAD/kukui-install/android.kpart" || \
        fail android_kpart_not_emmc
    grep -a -q 'console=ttynull' "$PAYLOAD/kukui-install/menu.kpart" || \
        fail menu_cmdline_mismatch
    SUPER_PART=$(part_by_name super) || fail no_super_partition
    ANDROID_PART=$(part_by_name android_kernel) || fail no_android_kernel_partition
    MENU_PART=$(part_by_name menu_kernel) || fail no_menu_kernel_partition
    DATA_PART=$(part_by_name userdata) || fail no_userdata_partition
    [ "$(cat "/sys/class/block/$SUPER_PART/size")" = 16777216 ] || \
        fail super_not_8gib
    bytes=$(stat -c %s "$PAYLOAD/kukui-install/android.kpart")
    need=$(((bytes + 511) / 512))
    [ "$(cat "/sys/class/block/$ANDROID_PART/size")" -ge "$need" ] || \
        fail android_kernel_too_small
    bytes=$(stat -c %s "$PAYLOAD/kukui-install/menu.kpart")
    need=$(((bytes + 511) / 512))
    [ "$(cat "/sys/class/block/$MENU_PART/size")" -ge "$need" ] || \
        fail menu_kernel_too_small
    fstype=$(blkid -s TYPE -o value "/dev/block/$DATA_PART" 2>/dev/null || true)
    [ "$fstype" = f2fs ] || fail userdata_not_f2fs "fstype=${fstype:-unread}"
    log "userdata $(blkid -s UUID -o value "/dev/block/$DATA_PART" 2>/dev/null || true)"
    MENU_ATTR=$(attr_flags "$MENU_PART")
    ANDROID_ATTR=$(attr_flags "$ANDROID_PART")
    [ -n "$MENU_ATTR" ] && [ -n "$ANDROID_ATTR" ] || fail no_kernel_attrs
    log "menu_kernel $MENU_ATTR"
    log "android_kernel $ANDROID_ATTR"
}

install_update() {
    local src dest src_hash got menu_now android_now
    require_update_layout
    refuse_mounted_emmc
    src=$(super_source "/dev/block/$SUPER_PART")
    dest="/dev/block/$SUPER_PART"
    write_status "state=running" "percent=10" "code=copying_super"
    dd if="$src" of="$dest" bs=1048576 conv=fsync || fail copy_super_failed
    got=$(hash_super "$dest")
    src_hash=$(hash_super "$src")
    [ "$src_hash" = "$got" ] || fail super_hash_mismatch
    write_status "state=running" "percent=80" "code=writing_android_and_menu"
    dd if="$PAYLOAD/kukui-install/android.kpart" of="/dev/block/$ANDROID_PART" \
        bs=1048576 conv=fsync || fail write_android_kernel_failed
    dd if="$PAYLOAD/kukui-install/menu.kpart" of="/dev/block/$MENU_PART" \
        bs=1048576 conv=fsync || fail write_menu_failed
    src_hash=$(hash_file "$PAYLOAD/kukui-install/android.kpart")
    got=$(hash_part "/dev/block/$ANDROID_PART" \
        "$(stat -c %s "$PAYLOAD/kukui-install/android.kpart")")
    [ "$src_hash" = "$got" ] || fail android_kernel_hash_mismatch
    src_hash=$(hash_file "$PAYLOAD/kukui-install/menu.kpart")
    got=$(hash_part "/dev/block/$MENU_PART" \
        "$(stat -c %s "$PAYLOAD/kukui-install/menu.kpart")")
    [ "$src_hash" = "$got" ] || fail menu_hash_mismatch
    menu_now=$(attr_flags "$MENU_PART")
    android_now=$(attr_flags "$ANDROID_PART")
    [ "$menu_now" = "$MENU_ATTR" ] || fail menu_attr_changed
    [ "$android_now" = "$ANDROID_ATTR" ] || fail android_attr_changed
    sync
    write_status "state=ready_reboot" "percent=100" "code=ready_update"
}

handle() {
    local dir="$1" op mode confirm resume
    STATUS_DIR=$dir
    op=$(sed -n 's/^op=//p' "$dir/request" | head -n 1)
    mode=$(sed -n 's/^mode=//p' "$dir/request" | head -n 1)
    confirm=$(sed -n 's/^confirm=//p' "$dir/request" | head -n 1)
    REQUEST_GIB=$(sed -n 's/^root_gib=//p' "$dir/request" | head -n 1)
    mv "$dir/request" "$dir/request.done"
    : > "$dir/log"
    require_identity
    mount_payload
    case "$op" in
        probe)
            if [ "$mode" = dual ]; then
                plan_dual || return 0
                resume=0
                if [ -e /sys/class/block/mmcblk0p4 ] && [ "$(part_name mmcblk0p4)" = menu_kernel ]; then
                    resume=1
                fi
                write_status "state=confirm" "mode=dual" "code=confirm_dual" \
                    "root_gib=$ROOT_GIB" "data_gib=$DATA_GIB" \
                    "min_gib=$MIN_GIB" "max_gib=$MAX_GIB" "resume=$resume"
            elif [ "$mode" = update ]; then
                require_update_layout || return 0
                write_status "state=confirm" "mode=update" "code=confirm_update" \
                    "format_userdata=no" \
                    "parent=$TARGET_PATH" \
                    "partitions=super android_kernel menu_kernel"
            else
                plan_android || return 0
                write_status "state=confirm" "mode=android" "code=confirm_android" \
                    "root_gib=0" "data_gib=$DATA_GIB"
            fi
            ;;
        go)
            [ "$confirm" = yes ] || fail no_confirm
            if [ "$mode" = dual ]; then
                [ -n "$REQUEST_GIB" ] || fail missing_root_gib
                install_dual
            elif [ "$mode" = android ]; then
                install_android_only
            elif [ "$mode" = update ]; then
                install_update
            else
                fail unknown_mode "mode=$mode"
            fi
            ;;
        *)
            fail unknown_request "op=$op"
            ;;
    esac
}

PATH=/system/bin:/vendor/bin:$PATH
for dir in \
    /data/media/0/Android/data/org.lineageos.kukuiinstaller/files \
    /storage/emulated/0/Android/data/org.lineageos.kukuiinstaller/files
do
    rm -f "$dir/status" "$dir/request"
done
while true; do
    for dir in \
        /data/media/0/Android/data/org.lineageos.kukuiinstaller/files \
        /storage/emulated/0/Android/data/org.lineageos.kukuiinstaller/files
    do
        if [ -f "$dir/request" ]; then
            ( handle "$dir" ) || true
        fi
    done
    sleep 1
done
