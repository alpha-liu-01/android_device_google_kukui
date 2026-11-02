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
    log "failed: $1"
    write_status "state=failed" "message=$1"
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
    boot=$(boot_disk) || fail "找不到启动盘上的 super"
    path=$(sysfs_of "$boot")
    case "$path" in
        *11201000.usb*|*11200000.usb*) ;;
        *) fail "启动盘不是 USB：$boot $path" ;;
    esac
    [ -e /sys/class/block/mmcblk0 ] || fail "没有 mmcblk0"
    target_path=$(sysfs_of mmcblk0)
    case "$target_path" in
        *11230000.mmc*) ;;
        *) fail "mmcblk0 不是这块 eMMC：$target_path" ;;
    esac
    case "$target_path" in
        *11201000.usb*|*11200000.usb*) fail "目标路径里有 USB 控制器" ;;
    esac
    rem=$(cat /sys/class/block/mmcblk0/removable 2>/dev/null || echo missing)
    [ "$rem" = 0 ] || fail "mmcblk0 removable=$rem"
    [ "$boot" != mmcblk0 ] || fail "启动盘和目标是同一块"
    BOOT_DISK=$boot
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
                    fail "挂不上 U 盘的 pmOS_boot"
                return 0
                ;;
        esac
    done
    fail "U 盘上没有 pmOS_boot"
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
    [ "$BLOCK_COUNT" -gt 0 ] && [ "$BLOCK_SIZE" -gt 0 ] || fail "读不到 ext4 的块数"
}

# toybox sh on this device evaluates $(( )) in 32-bit signed arithmetic.
# 16 * 1024 * 1024 * 1024 wraps to 0. Keep every product under 2^31.
plan_dual() {
    local used_blocks per_mib used_mib need_mib min_gib disk overhead room max_gib gib
    local free_after data_sectors
    read_tune
    per_mib=$((1048576 / BLOCK_SIZE))
    [ "$per_mib" -gt 0 ] || fail "ext4 块大小无法换算"
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
        fail "空闲空间不够同时留下 Linux 和 Android"
    fi
    max_gib=$((room / 2097152))
    if [ "$min_gib" -gt "$max_gib" ]; then
        fail "空闲空间不够同时留下 Linux 和 Android"
    fi
    MIN_GIB=$min_gib
    MAX_GIB=$max_gib
    if [ -n "${REQUEST_GIB:-}" ]; then
        case "$REQUEST_GIB" in
            *[!0-9]*) fail "Linux 根分区要写成整数 GiB" ;;
        esac
        if [ "${#REQUEST_GIB}" -gt 4 ]; then
            fail "Linux 根分区要在 ${MIN_GIB} 到 ${MAX_GIB} GiB 之间"
        fi
        gib=$(printf '%s' "$REQUEST_GIB" | sed 's/^0*//')
        [ -n "$gib" ] || gib=0
        gib=$((gib + 0))
        if [ "$gib" -lt "$MIN_GIB" ] || [ "$gib" -gt "$MAX_GIB" ]; then
            fail "Linux 根分区要在 ${MIN_GIB} 到 ${MAX_GIB} GiB 之间"
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
        fail "空闲空间不够同时留下 Linux 和 Android"
    fi
    DATA_GIB=$((data_sectors / 2097152))
    DATA_SECTORS=$data_sectors
}

plan_android() {
    local disk data_sectors
    disk=$(cat /sys/class/block/mmcblk0/size)
    DISK_SECTORS=$disk
    data_sectors=$((disk - 17940480 - 64))
    [ "$data_sectors" -gt 16777216 ] || fail "eMMC 放不下 8 GiB 的 super"
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
        /dev/block/mmcblk0 || fail "设置内核槽 $part 的优先级失败"
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
        /dev/block/mmcblk0 || fail "设置内核槽 $part 的优先级失败"
}

part_name() {
    sed -n 's/^PARTNAME=//p' "/sys/class/block/$1/uevent" | head -n 1
}

expect_part() {
    local got
    got=$(part_name "$1")
    [ "$got" = "$2" ] || fail "$1 的名字是 ${got:-空}，不是 $2"
}

super_source() {
    local src base path dest_disk
    src=$(readlink -f /dev/block/by-name/super)
    base=$(basename "$src")
    if [ -d "/sys/class/block/$base/slaves" ]; then
        base=$(ls "/sys/class/block/$base/slaves" 2>/dev/null | head -n 1)
        [ -n "$base" ] || fail "super 没有下层磁盘"
    fi
    base=$(disk_of "$base")
    path=$(sysfs_of "$base")
    case "$path" in
        *11201000.usb*|*11200000.usb*) ;;
        *) fail "super 的来源不是 USB：$base $path" ;;
    esac
    dest_disk=$(disk_of "$(basename "$(readlink -f "$1")")")
    [ "$dest_disk" != "$base" ] || fail "super 的来源和目标是同一个磁盘"
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
        log "保留已有的内核和分区表备份"
        return 0
    fi
    log "备份 mmcblk0p1 和分区表"
    dd if=/dev/block/mmcblk0p1 of="$PAYLOAD/kukui-install/backup/mmcblk0p1.kpart" bs=1048576 conv=fsync || \
        fail "备份内核槽失败"
    sgdisk --backup="$PAYLOAD/kukui-install/backup/mmcblk0.gpt" /dev/block/mmcblk0 || \
        fail "备份分区表失败"
    sync
}

refuse_mounted_emmc() {
    if grep -q mmcblk0 /proc/mounts 2>/dev/null; then
        fail "eMMC 上有分区挂着，拒绝写入"
    fi
}

set_kernel_attr_off() {
    local part="$1" bit
    # Priority 0 and tries 0 until the final commit. A half-written
    # kernel slot must not become what Ctrl+D boots.
    for bit in 48 49 50 51 52 53 54 55 56; do
        sgdisk --attributes="$part":clear:"$bit" /dev/block/mmcblk0 || \
            fail "清掉内核槽 $part 的优先级失败"
    done
}

check_payload() {
    [ -f "$PAYLOAD/kukui-install/android.kpart" ] || fail "U 盘上没有 android.kpart"
    [ -f "$PAYLOAD/kukui-install/android/Image" ] || fail "U 盘上没有 Android 内核"
    [ -f "$PAYLOAD/kukui-install/android/cmdline" ] || fail "U 盘上没有 Android 命令行"
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
    write_status "state=running" "percent=5" "message=备份内核槽"
    backup_kernel
    write_status "state=running" "percent=15" "message=写入分区表"
    sgdisk --zap-all /dev/block/mmcblk0 || fail "清空分区表失败"
    # This sgdisk rejects -a. Explicit sector numbers are already 1 MiB aligned.
    sgdisk \
        --new=1:8192:73727 --change-name=1:pmOS_kernel --typecode=1:FE3A2A5D-4F32-41A7-B725-ACCC3285A309 \
        --new=2:73728:1122303 --change-name=2:pmOS_boot --typecode=2:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
        --new=3:1122304:17899519 --change-name=3:super --typecode=3:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
        --new=4:17899520:17932287 --change-name=4:metadata --typecode=4:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
        --new=5:17932288:17940479 --change-name=5:misc --typecode=5:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
        --new=6:17940480:0 --change-name=6:userdata --typecode=6:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
        /dev/block/mmcblk0 || fail "建立 Android 分区失败"
    reread
    expect_part mmcblk0p1 pmOS_kernel
    expect_part mmcblk0p3 super
    expect_part mmcblk0p4 metadata
    expect_part mmcblk0p6 userdata
    write_status "state=running" "percent=30" "message=写入 Android 内核"
    dd if="$PAYLOAD/kukui-install/android.kpart" of=/dev/block/mmcblk0p1 bs=1048576 conv=fsync || \
        fail "写入内核失败"
    src_hash=$(hash_file "$PAYLOAD/kukui-install/android.kpart")
    got=$(hash_part /dev/block/mmcblk0p1 "$(stat -c %s "$PAYLOAD/kukui-install/android.kpart")")
    [ "$src_hash" = "$got" ] || fail "内核读回不一致"
    write_status "state=running" "percent=45" "message=复制 super"
    dd if="$(super_source /dev/block/mmcblk0p3)" of=/dev/block/mmcblk0p3 bs=1048576 conv=fsync || fail "复制 super 失败"
    got=$(hash_super /dev/block/mmcblk0p3)
    src_hash=$(hash_super /dev/block/by-name/super)
    [ "$src_hash" = "$got" ] || fail "super 读回不一致"
    write_status "state=running" "percent=85" "message=格式化 metadata 和 userdata"
    mke2fs -t ext4 -F -L metadata /dev/block/mmcblk0p4 || fail "格式化 metadata 失败"
    dd if=/dev/zero of=/dev/block/mmcblk0p5 bs=1048576 count=4 conv=fsync status=none || true
    make_f2fs -f -g android -O encrypt,extra_attr,project_quota,quota,compression /dev/block/mmcblk0p6 || \
        fail "格式化 userdata 失败"
    set_kernel_attr_full 1
    sync
    write_status "state=ready_reboot" "percent=100" "message=拔掉 U 盘，再开机。Ctrl+D 进入 eMMC 上的 Android。"
}

install_dual() {
    local end src_hash got expect live fit_bytes ec current args n
    local menu_start menu_end android_start android_end menu_files_start menu_files_end
    local super_start super_end meta_start meta_end misc_start misc_end data_start
    check_payload
    [ -f "$PAYLOAD/kukui-install/menu.kpart" ] || fail "U 盘上没有菜单内核"
    [ -f "$PAYLOAD/kukui-install/linux/Image" ] || fail "U 盘上没有 Linux 内核"
    [ -f "$PAYLOAD/kukui-install/linux.kpart.sha256" ] || fail "U 盘上没有 Linux 内核校验"
    [ -f "$PAYLOAD/kukui-install/linux/kernel.bytes" ] || fail "U 盘上没有 Linux 内核长度"
    plan_dual
    expect=$(tr -d ' \n' < "$PAYLOAD/kukui-install/linux.kpart.sha256")
    fit_bytes=$(tr -d ' \n' < "$PAYLOAD/kukui-install/linux/kernel.bytes")
    live=$(hash_part /dev/block/mmcblk0p1 "$fit_bytes")
    [ "$live" = "$expect" ] || fail "eMMC 上的 Linux 内核和安装器里的副本不一致"
    refuse_mounted_emmc
    write_status "state=running" "percent=5" "message=备份内核槽。这一步很快。"
    backup_kernel
    write_status "state=running" "percent=15" \
        "message=正在检查 Linux 根分区。这一步可能要几分钟，百分比会停在这里。请不要退出，也不要关机。"
    e2fsck -f -y /dev/block/mmcblk0p3
    ec=$?
    [ "$ec" -le 2 ] || fail "e2fsck 失败（$ec）"
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
        write_status "state=running" "percent=30" \
            "message=正在缩小 Linux 根分区。这一步可能要几分钟，百分比会停在这里。请不要退出，也不要关机。"
        resize2fs /dev/block/mmcblk0p3 "${ROOT_GIB}G" || fail "resize2fs 失败"
    elif [ "$current" -lt "$ROOT_SECTORS" ]; then
        log "根分区比目标小，先扩大分区"
    else
        log "根分区已经是 ${ROOT_GIB} GiB，不再缩小"
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
        log "分区表已经是目标布局，不再改分区"
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
        write_status "state=running" "percent=40" "message=正在调整分区表。"
        # shellcheck disable=SC2086
        sgdisk $args /dev/block/mmcblk0 > "$STATUS_DIR/sgdisk.txt" 2>&1
        ec=$?
        log "sgdisk $(tr '\n' ' ' < "$STATUS_DIR/sgdisk.txt")"
        [ "$ec" -eq 0 ] || fail "建立双系统分区失败"
        reread
        if [ "$current" -lt "$ROOT_SECTORS" ]; then
            resize2fs /dev/block/mmcblk0p3 "${ROOT_GIB}G" || fail "扩大根分区失败"
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
    write_status "state=running" "percent=55" "message=正在写入两个内核槽。"
    dd if="$PAYLOAD/kukui-install/menu.kpart" of=/dev/block/mmcblk0p4 bs=1048576 conv=fsync || fail "写入菜单失败"
    dd if="$PAYLOAD/kukui-install/android.kpart" of=/dev/block/mmcblk0p5 bs=1048576 conv=fsync || fail "写入 Android 内核失败"
    src_hash=$(hash_file "$PAYLOAD/kukui-install/menu.kpart")
    got=$(hash_part /dev/block/mmcblk0p4 "$(stat -c %s "$PAYLOAD/kukui-install/menu.kpart")")
    [ "$src_hash" = "$got" ] || fail "菜单读回不一致"
    src_hash=$(hash_file "$PAYLOAD/kukui-install/android.kpart")
    got=$(hash_part /dev/block/mmcblk0p5 "$(stat -c %s "$PAYLOAD/kukui-install/android.kpart")")
    [ "$src_hash" = "$got" ] || fail "Android 内核读回不一致"
    write_status "state=running" "percent=65" "message=写入启动菜单文件"
    mke2fs -t ext4 -F -L bootmenu /dev/block/mmcblk0p6 || fail "格式化 bootmenu 失败"
    mkdir -p /mnt/kukui-bootmenu
    mount -t ext4 /dev/block/mmcblk0p6 /mnt/kukui-bootmenu || fail "挂载 bootmenu 失败"
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
    [ -f "$PAYLOAD/kukui-install/android/initrd" ] || fail "U 盘上没有 Android initrd"
    expect_part mmcblk0p2 pmOS_boot
    mkdir -p /mnt/kukui-pmosboot
    mount -t ext4 -o rw /dev/block/mmcblk0p2 /mnt/kukui-pmosboot || fail "挂载 Linux 启动分区失败"
    cp "$PAYLOAD/kukui-install/android/initrd" /mnt/kukui-pmosboot/kukui-android.initrd
    sync
    umount /mnt/kukui-pmosboot
    write_status "state=running" "percent=75" \
        "message=正在把 super 复制到 eMMC。这一步可能要几分钟，百分比会停在这里。请不要退出，也不要关机。"
    dd if="$(super_source /dev/block/mmcblk0p7)" of=/dev/block/mmcblk0p7 bs=1048576 conv=fsync || fail "复制 super 失败"
    got=$(hash_super /dev/block/mmcblk0p7)
    src_hash=$(hash_super /dev/block/by-name/super)
    [ "$src_hash" = "$got" ] || fail "super 读回不一致"
    write_status "state=running" "percent=90" "message=格式化 metadata 和 userdata"
    mke2fs -t ext4 -F -L metadata /dev/block/mmcblk0p8 || fail "格式化 metadata 失败"
    dd if=/dev/zero of=/dev/block/mmcblk0p9 bs=1048576 count=4 conv=fsync status=none || true
    make_f2fs -f -g android -O encrypt,extra_attr,project_quota,quota,compression /dev/block/mmcblk0p10 || \
        fail "格式化 userdata 失败"
    write_status "state=running" "percent=96" "message=切换默认启动项"
    set_kernel_attr_full 4
    set_kernel_attr_low 1
    set_kernel_attr_low 5
    sync
    write_status "state=ready_reboot" "percent=100" "message=拔掉 U 盘，再开机。Ctrl+D 进入菜单。"
}

handle() {
    local dir="$1" op mode confirm note
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
                note=""
                if [ -e /sys/class/block/mmcblk0p4 ] && [ "$(part_name mmcblk0p4)" = menu_kernel ]; then
                    note=" 上次写入停在半路，Linux 还在，启动优先级还没改。这次会接着写完。"
                fi
                write_status "state=confirm" "mode=dual" \
                    "root_gib=$ROOT_GIB" "data_gib=$DATA_GIB" \
                    "min_gib=$MIN_GIB" "max_gib=$MAX_GIB" \
                    "message=Linux 根分区 ${ROOT_GIB} GiB，可填 ${MIN_GIB} 到 ${MAX_GIB}。Android 数据分区约 ${DATA_GIB} GiB。${note}"
            else
                plan_android || return 0
                write_status "state=confirm" "mode=android" \
                    "root_gib=0" "data_gib=$DATA_GIB" \
                    "message=eMMC 上的 postmarketOS 会被删掉。Android 数据分区约 ${DATA_GIB} GiB。"
            fi
            ;;
        go)
            [ "$confirm" = yes ] || fail "没有确认"
            if [ "$mode" = dual ]; then
                [ -n "$REQUEST_GIB" ] || fail "没有 Linux 根分区的大小"
                install_dual
            elif [ "$mode" = android ]; then
                install_android_only
            else
                fail "未知模式 $mode"
            fi
            ;;
        *)
            fail "未知请求 $op"
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
