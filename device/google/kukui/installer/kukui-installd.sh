#!/system/bin/sh
# Install the running USB Android onto the Krane eMMC.
# The USB kernel slot is never written. Nothing happens until a request
# file contains confirm=yes.
set -u

PAYLOAD=""
STATUS_DIR=""
DISK_SECTORS=0
# Comma-separated step codes of the running install, sent with every
# status so the app can list them.
STEPS=""

log() {
    echo "$1"
    if [ -n "$STATUS_DIR" ]; then
        printf '%s\n' "$1" >> "$STATUS_DIR/log"
        chmod 644 "$STATUS_DIR/log" 2>/dev/null || true
    fi
}

write_status() {
    local tmp="$STATUS_DIR/status.tmp"
    printf '%s\n' "$@" "steps=$STEPS" > "$tmp"
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
    # Refuse before any size math. A disk that is not this postmarketOS
    # layout must not be shrunk.
    require_linux_layout
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

# copy: partition 1 is at most 32 MiB, the kernel slot this installer writes.
# skip: it is missing or larger. ChromeOS puts the large STATE filesystem
# there. Android-only erases the disk anyway, and that filesystem does not
# fit on the USB boot partition.
describe_kernel_backup() {
    local sectors
    sectors=$(cat /sys/class/block/mmcblk0p1/size 2>/dev/null || echo 0)
    case "$sectors" in
        ''|*[!0-9]*) printf 'skip\n'; return ;;
    esac
    # More than five digits is already past 32 MiB. Avoid a 32-bit overflow.
    if [ "${#sectors}" -gt 5 ] || [ "$sectors" -eq 0 ] || [ "$sectors" -gt 65536 ]; then
        printf 'skip\n'
        return
    fi
    printf 'copy\n'
}

backup_kernel() {
    local action
    mkdir -p "$PAYLOAD/kukui-install/backup"
    action=$(describe_kernel_backup)
    if [ ! -f "$PAYLOAD/kukui-install/backup/mmcblk0.gpt" ]; then
        log "backing up gpt"
        sgdisk --backup="$PAYLOAD/kukui-install/backup/mmcblk0.gpt" /dev/block/mmcblk0 || \
            fail backup_gpt_failed
    else
        log "keeping existing gpt backup"
    fi
    if [ "$action" = copy ]; then
        if [ -f "$PAYLOAD/kukui-install/backup/mmcblk0p1.kpart" ]; then
            log "keeping existing kernel backup"
        else
            log "backing up mmcblk0p1"
            dd if=/dev/block/mmcblk0p1 of="$PAYLOAD/kukui-install/backup/mmcblk0p1.kpart" \
                bs=1048576 conv=fsync || fail backup_kernel_failed
        fi
    else
        log "mmcblk0p1 is not a 32 MiB kernel slot; not copying it"
    fi
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

require_linux_layout() {
    local fstype
    [ "$(part_name mmcblk0p1)" = pmOS_kernel ] || fail not_pmos_layout
    [ "$(part_name mmcblk0p2)" = pmOS_boot ] || fail not_pmos_layout
    [ "$(part_name mmcblk0p3)" = pmOS_root ] || fail not_pmos_layout
    [ "$(cat /sys/class/block/mmcblk0p1/start)" = 8192 ] || fail not_pmos_layout
    [ "$(cat /sys/class/block/mmcblk0p2/start)" = 73728 ] || fail not_pmos_layout
    [ "$(cat /sys/class/block/mmcblk0p3/start)" = 1122304 ] || fail not_pmos_layout
    # Official postmarketOS formats pmOS_boot as ext2. The menu mounts it
    # read-only with type ext4. This kernel's ext4 driver accepts that.
    fstype=$(blkid -s TYPE -o value /dev/block/mmcblk0p2 2>/dev/null || true)
    case "$fstype" in
        ext2|ext3|ext4) ;;
        *) fail linux_boot_not_ext4 "fstype=${fstype:-unread}" ;;
    esac
}

check_android_kpart() {
    local bytes
    [ -f "$PAYLOAD/kukui-install/android.kpart" ] || fail missing_android_kpart
    grep -a -q 'androidboot.boot_devices=soc/11230000.mmc' \
        "$PAYLOAD/kukui-install/android.kpart" || \
        fail android_kpart_not_emmc
    if grep -a -q '11201000.usb' "$PAYLOAD/kukui-install/android.kpart"; then
        fail android_kpart_not_emmc
    fi
    bytes=$(stat -c %s "$PAYLOAD/kukui-install/android.kpart")
    # The eMMC kernel slot is 32 MiB. 33554432 fits in signed 32-bit.
    [ "$bytes" -gt 0 ] && [ "$bytes" -le 33554432 ] || fail android_kernel_too_small
}

check_menu_kpart() {
    local bytes
    [ -f "$PAYLOAD/kukui-install/menu.kpart" ] || fail missing_menu
    grep -a -q 'console=ttynull' "$PAYLOAD/kukui-install/menu.kpart" || \
        fail menu_cmdline_mismatch
    bytes=$(stat -c %s "$PAYLOAD/kukui-install/menu.kpart")
    [ "$bytes" -gt 0 ] && [ "$bytes" -le 33554432 ] || fail menu_kernel_too_small
}

hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

hash_part() {
    local dev="$1" bytes="$2" mib
    # bytes stays under 32 MiB here. Super is checked area by area
    # (verify_super).
    mib=$(((bytes + 1048575) / 1048576))
    dd if="$dev" bs=1048576 count="$mib" status=none | \
        head -c "$bytes" | sha256sum | awk '{print $1}'
}

# Super holds the LP metadata in its first sectors and the logical
# partitions at the extents the metadata lists. Nothing reads the rest,
# so only those areas are copied and checked: about 1.3 GiB of 8 GiB.
# The eMMC partition is discarded first, so the free space holds no old
# data either. The source is read once: tee feeds the same bytes to
# sha256sum while they are written, and the check then reads back only
# the eMMC. All sizes are MiB because mksh arithmetic is 32-bit.

# super_regions <file>: writes "<start MiB> <length MiB> <name>" lines,
# the partitions first and the metadata area last. lpdump without a path
# reads the super this system runs from, which super_source has checked
# is the USB disk. Extents are 1 MiB aligned; rounding the end up only
# copies more of the same source layout.
super_regions() {
    local out="$1" first
    lpdump > "$STATUS_DIR/lpdump.txt" 2>&1 || fail super_no_metadata
    first=$(awk '/First sector:/ { print $3; exit }' "$STATUS_DIR/lpdump.txt")
    [ -n "$first" ] && [ "$first" -gt 0 ] || fail super_no_metadata
    awk '$1 == "Name:" { name = $2 }
         $2 == ".." && $4 == "linear" && $5 == "super" {
            s = $6; n = $3 - $1 + 1
            printf "%d %d %s\n", int(s / 2048), int((s % 2048 + n + 2047) / 2048), name
         }' "$STATUS_DIR/lpdump.txt" > "$out"
    [ -s "$out" ] || fail super_no_metadata
    echo "0 $(((first + 2047) / 2048)) metadata" >> "$out"
    log "super areas (MiB start length name): $(tr '\n' ' ' < "$out")"
}

# Progress lines. They replace the status file every two seconds and do
# not go into the log.
write_progress() {
    local tmp="$STATUS_DIR/status.tmp"
    printf '%s\n' "$@" "steps=$STEPS" > "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "$STATUS_DIR/status"
}

# watch_mib <pid> <io field> <code> <percent from> <percent to>
#           <MiB done before> <MiB total> <area name> <area MiB>
watch_mib() {
    local pid="$1" field="$2" code="$3" from="$4" to="$5" base="$6" total="$7"
    local part="$8" part_mib="$9" mib done pct
    while kill -0 "$pid" 2>/dev/null; do
        mib=$(awk -v f="$field:" '$1 == f { printf "%d", $2 / 1048576 }' \
            "/proc/$pid/io" 2>/dev/null)
        if [ -n "$mib" ]; then
            [ "$mib" -gt "$part_mib" ] && mib=$part_mib
            done=$((base + mib))
            pct=$((from + (to - from) * done / total))
            [ "$pct" -ge "$to" ] && pct=$((to - 1))
            write_progress "state=running" "percent=$pct" "code=$code" \
                "done_mib=$done" "total_mib=$total" \
                "part=$part" "part_done_mib=$mib" "part_mib=$part_mib"
        fi
        sleep 2
    done
}

# copy_super <source> <dest> <percent from> <percent to>
# The metadata area comes last, so an interrupted copy leaves a super
# without a partition table rather than one pointing at half written
# partitions. Leaves "<start> <len> <name> <sha256>" lines of the source
# in $STATUS_DIR/super-src.list for verify_super.
copy_super() {
    local src="$1" dest="$2" regions="$STATUS_DIR/super-regions"
    local list="$STATUS_DIR/super-src.list" fifo="$STATUS_DIR/copy.fifo"
    local out="$STATUS_DIR/copy.sha" total done pid hpid start len name
    super_regions "$regions"
    total=$(awk '{ t += $2 } END { print t }' "$regions")
    write_status "state=running" "percent=$3" "code=copying_super" \
        "done_mib=0" "total_mib=$total" "part=discard"
    if blkdiscard "$dest" 2>/dev/null; then
        log "discarded $dest"
    else
        log "discard of $dest not supported, old data stays in free space"
    fi
    : > "$list"
    done=0
    while read -r start len name; do
        rm -f "$fifo" "$out"
        mkfifo "$fifo" || fail copy_super_failed
        sha256sum < "$fifo" > "$out" &
        hpid=$!
        dd if="$src" bs=1048576 skip="$start" count="$len" status=none | \
            tee "$fifo" | \
            dd of="$dest" bs=1048576 seek="$start" conv=notrunc,fsync status=none &
        pid=$!
        watch_mib "$pid" wchar copying_super "$3" "$4" "$done" "$total" "$name" "$len"
        wait "$pid" || fail copy_super_failed "part=$name"
        wait "$hpid"
        echo "$start $len $name $(awk '{ print $1 }' "$out")" >> "$list"
        log "copied $name ($len MiB)"
        done=$((done + len))
    done < "$regions"
    rm -f "$fifo" "$out"
}

# verify_super <dest> <percent from> <percent to>: reads every copied
# area back from the eMMC and compares it with the hash taken while it
# was copied.
verify_super() {
    local dest="$1" list="$STATUS_DIR/super-src.list" out="$STATUS_DIR/verify.sha"
    local total done pid start len name want got
    total=$(awk '{ t += $2 } END { print t }' "$list")
    # Right after the copy most of it is still in the page cache. Drop it
    # so the check reads the flash, not RAM.
    sync
    echo 3 > /proc/sys/vm/drop_caches
    done=0
    while read -r start len name want; do
        rm -f "$out"
        dd if="$dest" bs=1048576 skip="$start" count="$len" status=none | \
            sha256sum > "$out" &
        pid=$!
        watch_mib "$pid" rchar verifying_super "$2" "$3" "$done" "$total" "$name" "$len"
        wait "$pid"
        got=$(awk '{ print $1 }' "$out")
        [ "$got" = "$want" ] || fail super_hash_mismatch "part=$name"
        log "checked $name"
        done=$((done + len))
    done < "$list"
    rm -f "$out"
}

install_android_only() {
    local src_hash got
    STEPS="backing_up_kernel,writing_gpt,writing_android_kernel,copying_super,verifying_super,formatting_data"
    check_android_kpart
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
    copy_super "$(super_source /dev/block/mmcblk0p3)" /dev/block/mmcblk0p3 40 75
    verify_super /dev/block/mmcblk0p3 75 85
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
    local end src_hash got ec current args n
    local menu_start menu_end android_start android_end menu_files_start menu_files_end
    local super_start super_end meta_start meta_end misc_start misc_end data_start
    STEPS="backing_up_kernel,checking_linux_root,shrinking_linux_root,adjusting_gpt,writing_kernel_slots,writing_menu_files,copying_super,verifying_super,formatting_data,switching_boot"
    check_android_kpart
    check_menu_kpart
    plan_dual
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
    # The menu mounts this partition and does not read anything inside it.
    # Leave pmOS_boot alone so the existing Linux initramfs stays there.
    write_status "state=running" "percent=65" "code=writing_menu_files"
    mke2fs -t ext4 -F -L bootmenu /dev/block/mmcblk0p6 || fail format_bootmenu_failed
    copy_super "$(super_source /dev/block/mmcblk0p7)" /dev/block/mmcblk0p7 70 85
    verify_super /dev/block/mmcblk0p7 85 90
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
    grep -a -q 'androidboot.boot_devices=soc/11230000.mmc' \
        "$PAYLOAD/kukui-install/android.kpart" || \
        fail android_kpart_not_emmc
    SUPER_PART=$(part_by_name super) || fail no_super_partition
    if ANDROID_PART=$(part_by_name android_kernel); then
        # Android and Linux: separate android_kernel and menu_kernel slots.
        UPDATE_LAYOUT=dual
        [ -f "$PAYLOAD/kukui-install/menu.kpart" ] || fail missing_menu
        grep -a -q 'console=ttynull' "$PAYLOAD/kukui-install/menu.kpart" || \
            fail menu_cmdline_mismatch
        MENU_PART=$(part_by_name menu_kernel) || fail no_menu_kernel_partition
    elif [ "$(part_name mmcblk0p1 2>/dev/null)" = pmOS_kernel ] && \
         [ "$(part_name mmcblk0p3 2>/dev/null)" = super ] && \
         [ "$(part_name mmcblk0p6 2>/dev/null)" = userdata ] && \
         ! part_by_name pmOS_root > /dev/null; then
        # Android only (install_android_only): Android's kernel is in
        # pmOS_kernel (p1) and there is no menu. Only touch p1 if it
        # already holds an eMMC Android kernel.
        UPDATE_LAYOUT=android
        ANDROID_PART=mmcblk0p1
        MENU_PART=
        dd if=/dev/block/mmcblk0p1 bs=1048576 count=32 status=none | \
            grep -a -q 'androidboot.boot_devices=soc/11230000.mmc' || \
            fail no_android_kernel_partition
    else
        fail no_android_kernel_partition
    fi
    log "update layout $UPDATE_LAYOUT"
    DATA_PART=$(part_by_name userdata) || fail no_userdata_partition
    [ "$(cat "/sys/class/block/$SUPER_PART/size")" = 16777216 ] || \
        fail super_not_8gib
    bytes=$(stat -c %s "$PAYLOAD/kukui-install/android.kpart")
    need=$(((bytes + 511) / 512))
    [ "$(cat "/sys/class/block/$ANDROID_PART/size")" -ge "$need" ] || \
        fail android_kernel_too_small
    if [ "$UPDATE_LAYOUT" = dual ]; then
        bytes=$(stat -c %s "$PAYLOAD/kukui-install/menu.kpart")
        need=$(((bytes + 511) / 512))
        [ "$(cat "/sys/class/block/$MENU_PART/size")" -ge "$need" ] || \
            fail menu_kernel_too_small
    fi
    fstype=$(blkid -s TYPE -o value "/dev/block/$DATA_PART" 2>/dev/null || true)
    [ "$fstype" = f2fs ] || fail userdata_not_f2fs "fstype=${fstype:-unread}"
    log "userdata $(blkid -s UUID -o value "/dev/block/$DATA_PART" 2>/dev/null || true)"
    ANDROID_ATTR=$(attr_flags "$ANDROID_PART")
    [ -n "$ANDROID_ATTR" ] || fail no_kernel_attrs
    log "android kernel $ANDROID_PART $ANDROID_ATTR"
    if [ "$UPDATE_LAYOUT" = dual ]; then
        MENU_ATTR=$(attr_flags "$MENU_PART")
        [ -n "$MENU_ATTR" ] || fail no_kernel_attrs
        log "menu_kernel $MENU_ATTR"
    fi
}

install_update() {
    local src dest src_hash got menu_now android_now
    require_update_layout
    if [ "$UPDATE_LAYOUT" = dual ]; then
        STEPS="copying_super,verifying_super,writing_android_and_menu"
    else
        STEPS="copying_super,verifying_super,writing_android_kernel"
    fi
    refuse_mounted_emmc
    src=$(super_source "/dev/block/$SUPER_PART")
    dest="/dev/block/$SUPER_PART"
    copy_super "$src" "$dest" 5 75
    verify_super "$dest" 75 85
    if [ "$UPDATE_LAYOUT" = dual ]; then
        write_status "state=running" "percent=85" "code=writing_android_and_menu"
    else
        write_status "state=running" "percent=85" "code=writing_android_kernel"
    fi
    dd if="$PAYLOAD/kukui-install/android.kpart" of="/dev/block/$ANDROID_PART" \
        bs=1048576 conv=fsync || fail write_android_kernel_failed
    if [ "$UPDATE_LAYOUT" = dual ]; then
        dd if="$PAYLOAD/kukui-install/menu.kpart" of="/dev/block/$MENU_PART" \
            bs=1048576 conv=fsync || fail write_menu_failed
    fi
    src_hash=$(hash_file "$PAYLOAD/kukui-install/android.kpart")
    got=$(hash_part "/dev/block/$ANDROID_PART" \
        "$(stat -c %s "$PAYLOAD/kukui-install/android.kpart")")
    [ "$src_hash" = "$got" ] || fail android_kernel_hash_mismatch
    if [ "$UPDATE_LAYOUT" = dual ]; then
        src_hash=$(hash_file "$PAYLOAD/kukui-install/menu.kpart")
        got=$(hash_part "/dev/block/$MENU_PART" \
            "$(stat -c %s "$PAYLOAD/kukui-install/menu.kpart")")
        [ "$src_hash" = "$got" ] || fail menu_hash_mismatch
        menu_now=$(attr_flags "$MENU_PART")
        [ "$menu_now" = "$MENU_ATTR" ] || fail menu_attr_changed
    fi
    android_now=$(attr_flags "$ANDROID_PART")
    [ "$android_now" = "$ANDROID_ATTR" ] || fail android_attr_changed
    sync
    if [ "$UPDATE_LAYOUT" = dual ]; then
        write_status "state=ready_reboot" "percent=100" "code=ready_update"
    else
        write_status "state=ready_reboot" "percent=100" "code=ready_update_android"
    fi
}

handle() {
    local dir="$1" op mode confirm resume ec action
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
                if [ "$UPDATE_LAYOUT" = dual ]; then
                    write_status "state=confirm" "mode=update" "code=confirm_update" \
                        "format_userdata=no" \
                        "parent=$TARGET_PATH" \
                        "partitions=super android_kernel menu_kernel"
                else
                    write_status "state=confirm" "mode=update" "code=confirm_update_android" \
                        "format_userdata=no" \
                        "parent=$TARGET_PATH" \
                        "partitions=super pmOS_kernel"
                fi
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
        dry)
            if [ "$mode" = dual ]; then
                check_android_kpart
                check_menu_kpart
                plan_dual || return 0
                refuse_mounted_emmc
                log "e2fsck -n /dev/block/mmcblk0p3"
                e2fsck -n /dev/block/mmcblk0p3 >> "$STATUS_DIR/log" 2>&1
                ec=$?
                log "e2fsck -n exit $ec"
                [ "$ec" -le 4 ] || fail e2fsck_failed "exit_code=$ec"
                write_status "state=dry_ok" "mode=dual" "code=dry_dual" \
                    "root_gib=$ROOT_GIB" "data_gib=$DATA_GIB" "e2fsck=$ec"
            elif [ "$mode" = update ]; then
                require_update_layout || return 0
                if [ "$UPDATE_LAYOUT" = dual ]; then
                    write_status "state=dry_ok" "mode=update" "code=dry_update" \
                        "parent=$TARGET_PATH"
                else
                    write_status "state=dry_ok" "mode=update" "code=dry_update_android" \
                        "parent=$TARGET_PATH"
                fi
            elif [ "$mode" = android ]; then
                check_android_kpart
                plan_android || return 0
                refuse_mounted_emmc
                action=$(describe_kernel_backup)
                log "kernel backup $action"
                write_status "state=dry_ok" "mode=android" "code=dry_android" \
                    "data_gib=$DATA_GIB" "backup=$action"
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
