#!/bin/bash
# Pack the eMMC Android FIT and the boot-menu FIT.
# Neither file is written to the USB kernel slot.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:?need a directory for the payloads}"
KEEP="${2:?need kukui-keep-emmc}"
MENU="${3:?need kukui-menu}"
MOD="$ROOT/device/google/kukui/prebuilt/6.18.62-mt81-kukui2"
DEVKEYS=/usr/share/vboot/devkeys
# FIT that supplies the shared kernel and ramdisk. The board DTB is
# replaced below, so this only has to match the kernel build.
KERNEL_FIT="${KUKUI_KERNEL_FIT:-$ROOT/work/phase4/kernel.kpart.camera}"
# Optional postmarketOS FIT for the legacy kexec/Linux payload (Krane only).
PMOS="${KUKUI_PMOS_FIT:-$ROOT/work/phase1/pmos-vmlinuz.kpart}"

if [[ -n "${KUKUI_DTB:-}" && -z "${KUKUI_BOARD:-}" ]]; then
    BOARD="$(basename "$KUKUI_DTB" .dtb)"
else
    BOARD="${KUKUI_BOARD:-krane}"
fi
[[ "$BOARD" =~ ^[A-Za-z0-9_.-]+$ ]] || {
    echo "invalid KUKUI_BOARD: $BOARD" >&2
    exit 1
}
DTB="${KUKUI_DTB:-}"
DTB_DESC="${KUKUI_DTB_DESC:-}"
DTB_COMPAT="${KUKUI_DTB_COMPAT:-}"

command -v dtc >/dev/null || { echo "dtc is required" >&2; exit 1; }
[[ -f "$KERNEL_FIT" ]] || {
    echo "missing KUKUI_KERNEL_FIT: $KERNEL_FIT" >&2
    exit 1
}

mkdir -p "$OUT"
work=$(mktemp -d /tmp/kukui-pack.XXXXXX)
trap 'rm -rf "$work"' EXIT

fit=$(mktemp)
futility vbutil_kernel --get-vmlinuz "$KERNEL_FIT" --vmlinuz-out "$fit"
# A Krane FIT can carry sku176 and sku0 before the ramdisk. Take the
# first image of each type instead of assuming three fixed indexes.
fit_index() {
    dumpimage -l "$1" | awk -v want="$2" '
        /^ Image / { idx=$2 }
        $0 ~ want && found == "" { found=idx }
        END {
            if (found == "") exit 1
            print found
        }
    '
}
dumpimage -T flat_dt -p "$(fit_index "$fit" "Type:[[:space:]]+Kernel Image")" \
    -o "$work/kernel.lzma" "$fit"
dumpimage -T flat_dt -p "$(fit_index "$fit" "Type:[[:space:]]+Flat Device Tree")" \
    -o "$work/board.dtb" "$fit"
dumpimage -T flat_dt -p "$(fit_index "$fit" "Type:[[:space:]]+RAMDisk")" \
    -o "$work/ramdisk.gz" "$fit"
lzma -dc "$work/kernel.lzma" > "$work/Image"

if [[ -n "$DTB" ]]; then
    [[ -f "$DTB" ]] || { echo "missing KUKUI_DTB: $DTB" >&2; exit 1; }
    cp -f "$DTB" "$work/board.dtb"
    DTB_DESC="${DTB_DESC:-$(basename "$DTB" .dtb)}"
else
    DTB_DESC="${DTB_DESC:-mt8183-kukui-krane-sku176}"
    DTB_COMPAT="${DTB_COMPAT:-google,krane-sku176}"
fi
[[ -n "$DTB_DESC" ]] || {
    echo "empty DTB description" >&2
    exit 1
}
# grep -q under pipefail reports failure when dtc is closed early.
board_text=$(dtc -I dtb -O dts "$work/board.dtb" 2>/dev/null || true)
if [[ -n "$DTB_COMPAT" ]]; then
    grep -q -F -- "$DTB_COMPAT" <<<"$board_text" || {
        echo "$work/board.dtb does not contain $DTB_COMPAT" >&2
        exit 1
    }
else
    grep -q -F -- 'google,' <<<"$board_text" || {
        echo "$work/board.dtb does not look like a Kukui DTB" >&2
        exit 1
    }
fi
# Krane sku0 is the same sku176 DTB with the AUO panel. A Krane FIT also
# carries the Kodama sku16 DTB, so one image boots both boards.
# Passing KUKUI_DTB for another board keeps that single DTB.
command -v fdtget >/dev/null || { echo "fdtget is required" >&2; exit 1; }
board_compat=$(fdtget "$work/board.dtb" / compatible)
case " $board_compat " in
    *" google,krane-sku176 "*)
        "$ROOT/bringup/kernel/krane-sku0-dtb.sh" "$work/board.dtb" "$work/krane-sku0.dtb"
        ;;
esac
sku0_images=""
sku0_confs=""
if [[ -f "$work/krane-sku0.dtb" ]]; then
    sku0_images='
        fdt-2 {
            description = "mt8183-kukui-krane-sku0";
            data = /incbin/("krane-sku0.dtb");
            type = "flat_dt";
            arch = "arm64";
            compression = "none";
            hash-1 { algo = "crc32"; };
        };'
    sku0_confs='
        conf-2 {
            description = "mt8183-kukui-krane-sku0";
            kernel = "kernel-1";
            fdt = "fdt-2";
            ramdisk = "ramdisk-1";
            loadables = "kernel-1";
        };'
fi
kodama_images=""
kodama_confs=""
if [[ -f "$work/krane-sku0.dtb" ]]; then
    linux_src="${LINUX_SRC:-$ROOT/work/phase2/linux-6.18.62}"
    LINUX_SRC="$linux_src" KUKUI_COMPAT=google,kodama-sku16 \
        "$ROOT/bringup/boards/build-dtb.sh" "$work/kodama-out"
    cp "$work/kodama-out/mt8183-kukui-kodama-sku16.dtb" "$work/kodama.dtb"
    kodama_text=$(dtc -I dtb -O dts "$work/kodama.dtb" 2>/dev/null || true)
    grep -q -F -- 'auo,b101uan08.3' <<<"$kodama_text" || {
        echo "kodama sku16 panel is not auo,b101uan08.3" >&2
        exit 1
    }
    kodama_images='
        fdt-3 {
            description = "mt8183-kukui-kodama-sku16";
            data = /incbin/("kodama.dtb");
            type = "flat_dt";
            arch = "arm64";
            compression = "none";
            hash-1 { algo = "crc32"; };
        };'
    kodama_confs='
        conf-3 {
            description = "mt8183-kukui-kodama-sku16";
            kernel = "kernel-1";
            fdt = "fdt-3";
            ramdisk = "ramdisk-1";
            loadables = "kernel-1";
        };'
fi

# eMMC ramdisk: the kernel FIT ramdisk with only /init replaced.
mkdir -p "$work/rd"
# Device nodes need root. devtmpfs covers /dev before init runs.
gzip -dc "$work/ramdisk.gz" | (cd "$work/rd" && cpio -id --quiet) || true
test -f "$work/rd/init.android"
test -d "$work/rd/lib/modules/6.18.62-mt81-kukui2"
cp "$KEEP" "$work/rd/init"
chmod 755 "$work/rd/init"
# kukui-keep reads this into memory and starts it after vendor is
# mounted. An init.rc in the ramdisk does not survive FreeRamdisk.
cp "$ROOT/device/google/kukui/kukui-wifi-reprobe.sh" "$work/rd/kukui-wifi-reprobe.sh"
chmod 755 "$work/rd/kukui-wifi-reprobe.sh"
(cd "$work/rd" && find . -print0 | sort -z | cpio --null -o -H newc --quiet | gzip -n > "$work/emmc-ramdisk.gz")

cat > "$work/android-cmd.txt" << 'EOF'
kern_guid=%U cros_secure lsm=landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,bpf console=tty0 loglevel=4 deferred_probe_timeout=30 androidboot.selinux=permissive androidboot.hardware=kukui androidboot.boot_devices=soc/11230000.mmc drm_client_lib.active=none mem_sleep_default=s2idle
EOF

# Menu ramdisk. No Android init. fbdev stays enabled so /dev/fb0 exists.
# ttynull keeps fbcon off that framebuffer; drm_client_lib.active=none
# would remove fb0 entirely. evdev.ko is what creates /dev/input/event*.
mkdir -p "$work/menu/lib/modules/6.18.62-mt81-kukui2"
cp "$MENU" "$work/menu/init"
chmod 755 "$work/menu/init"
for ko in evdev.ko hid-multitouch.ko hid-generic.ko i2c-hid.ko i2c-hid-of.ko i2c-hid-of-goodix.ko; do
    cp "$MOD/$ko" "$work/menu/lib/modules/6.18.62-mt81-kukui2/$ko"
done
(cd "$work/menu" && find . -print0 | sort -z | cpio --null -o -H newc --quiet > "$work/menu-ramdisk.cpio")

cat > "$work/menu-cmd.txt" << 'EOF'
kern_guid=%U console=ttynull loglevel=1 deferred_probe_timeout=30 vt.global_cursor_default=0
EOF

pack_one() {
    local ramdisk="$1" cmdline="$2" dest="$3"
    cat > "$work/kernel.its" << EOF
/dts-v1/;

/ {
    description = "Kernel Image image with one or more FDT blobs";
    #address-cells = <1>;
    images {
        kernel-1 {
            description = "Kernel Image";
            data = /incbin/("kernel.lzma");
            type = "kernel_noload";
            arch = "arm64";
            os = "linux";
            compression = "lzma";
            load = <0>;
            entry = <0>;
            hash-1 { algo = "crc32"; };
        };
        fdt-1 {
            description = "${DTB_DESC}";
            data = /incbin/("board.dtb");
            type = "flat_dt";
            arch = "arm64";
            compression = "none";
            hash-1 { algo = "crc32"; };
        };
${sku0_images}
${kodama_images}
        ramdisk-1 {
            description = "unavailable";
            data = /incbin/("${ramdisk}");
            type = "ramdisk";
            arch = "arm64";
            os = "linux";
            compression = "none";
            hash-1 { algo = "crc32"; };
        };
    };
    configurations {
        default = "conf-1";
        conf-1 {
            description = "${DTB_DESC}";
            kernel = "kernel-1";
            fdt = "fdt-1";
            ramdisk = "ramdisk-1";
            loadables = "kernel-1";
        };
${sku0_confs}
${kodama_confs}
    };
};
EOF
    # mkimage resolves incbin paths from the current directory.
    (cd "$work" && mkimage -D "-I dts -O dtb -p 2048" -f kernel.its image.itb)
    dd if=/dev/zero of="$work/bootloader.bin" bs=4096 count=1 status=none
    futility vbutil_kernel --pack "$dest" \
        --keyblock "$DEVKEYS/kernel.keyblock" \
        --signprivate "$DEVKEYS/kernel_data_key.vbprivk" \
        --version 1 \
        --config "$cmdline" \
        --bootloader "$work/bootloader.bin" \
        --vmlinuz "$work/image.itb" \
        --arch arm
    futility vbutil_kernel --verify "$dest" >/dev/null
}

if [[ "${MENU_ONLY:-}" != 1 ]]; then
    pack_one emmc-ramdisk.gz "$work/android-cmd.txt" "$OUT/android.kpart"
fi
pack_one menu-ramdisk.cpio "$work/menu-cmd.txt" "$OUT/menu.kpart"

if [[ "${MENU_ONLY:-}" == 1 ]]; then
    echo "menu.kpart $(stat -c %s "$OUT/menu.kpart") $(sha256sum "$OUT/menu.kpart" | awk '{print $1}')"
    echo "--- menu ---"
    futility dump_kernel_config "$OUT/menu.kpart"
    exit 0
fi

mkdir -p "$OUT/android"
cp "$work/Image" "$OUT/android/Image"
cp "$work/board.dtb" "$OUT/android/${BOARD}.dtb"
# kexec does not expand kern_guid=%U. The rest matches the eMMC FIT.
sed 's/^kern_guid=%U //' "$work/android-cmd.txt" > "$OUT/android/cmdline"

if [[ "$BOARD" == "krane" ]]; then
    mkdir -p "$OUT/linux"
    pmos=$(mktemp)
    futility vbutil_kernel --get-vmlinuz "$PMOS" --vmlinuz-out "$pmos"
    dumpimage -T flat_dt -p 0 -o "$work/pmos.lzma" "$pmos"
    dumpimage -T flat_dt -p 27 -o "$OUT/linux/krane.dtb" "$pmos"
    lzma -dc "$work/pmos.lzma" > "$OUT/linux/Image"
    # Image 27 is mt8183-kukui-krane-sku176 in the postmarketOS FIT.
    test "$(stat -c %s "$OUT/linux/krane.dtb")" = 61542
    futility dump_kernel_config "$PMOS" | sed 's/^kern_guid=%U //' > "$OUT/linux/cmdline"
    stat -c %s "$PMOS" > "$OUT/linux/kernel.bytes"
    sha256sum "$PMOS" | awk '{print $1}' > "$OUT/linux.kpart.sha256"
    rm -f "$pmos"
else
    echo "Skipping legacy Linux/kexec payload for $BOARD (Android-only bring-up)" >&2
fi
rm -f "$fit"

echo "android.kpart $(stat -c %s "$OUT/android.kpart") $(sha256sum "$OUT/android.kpart" | awk '{print $1}')"
echo "menu.kpart $(stat -c %s "$OUT/menu.kpart") $(sha256sum "$OUT/menu.kpart" | awk '{print $1}')"
futility dump_kernel_config "$OUT/android.kpart"
echo "--- menu ---"
futility dump_kernel_config "$OUT/menu.kpart"
