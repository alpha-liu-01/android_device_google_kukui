#!/bin/bash
# Pack the eMMC Android FIT and the boot-menu FIT.
# Neither file is written to the USB kernel slot.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:?need a directory for the payloads}"
KEEP="${2:?need kukui-keep-emmc}"
MENU="${3:?need kukui-menu}"
MOD="$ROOT/device/google/kukui/prebuilt/6.18.28-mt81-kukui2"
DEVKEYS=/usr/share/vboot/devkeys
CAMERA="$ROOT/work/phase4/kernel.kpart.camera"
PMOS="$ROOT/work/phase1/pmos-vmlinuz.kpart"

mkdir -p "$OUT"
work=$(mktemp -d /tmp/kukui-pack.XXXXXX)
trap 'rm -rf "$work"' EXIT

fit=$(mktemp)
futility vbutil_kernel --get-vmlinuz "$CAMERA" --vmlinuz-out "$fit"
dumpimage -T flat_dt -p 0 -o "$work/kernel.lzma" "$fit"
dumpimage -T flat_dt -p 1 -o "$work/krane.dtb" "$fit"
dumpimage -T flat_dt -p 2 -o "$work/ramdisk.gz" "$fit"
lzma -dc "$work/kernel.lzma" > "$work/Image"
test "$(stat -c %s "$work/krane.dtb")" = 65144

# eMMC ramdisk: the camera ramdisk with only /init replaced.
mkdir -p "$work/rd"
# Device nodes need root. devtmpfs covers /dev before init runs.
gzip -dc "$work/ramdisk.gz" | (cd "$work/rd" && cpio -id --quiet) || true
test -f "$work/rd/init.android"
test -d "$work/rd/lib/modules/6.18.28-mt81-kukui2"
cp "$KEEP" "$work/rd/init"
chmod 755 "$work/rd/init"
# kukui-keep reads this into memory and starts it after vendor is
# mounted. An init.rc in the ramdisk does not survive FreeRamdisk.
cp "$ROOT/device/google/kukui/kukui-wifi-reprobe.sh" "$work/rd/kukui-wifi-reprobe.sh"
chmod 755 "$work/rd/kukui-wifi-reprobe.sh"
(cd "$work/rd" && find . -print0 | sort -z | cpio --null -o -H newc --quiet | gzip -n > "$work/emmc-ramdisk.gz")

cat > "$work/android-cmd.txt" << 'EOF'
kern_guid=%U cros_secure lsm=landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,bpf console=tty0 loglevel=7 deferred_probe_timeout=30 androidboot.selinux=permissive androidboot.hardware=kukui androidboot.boot_devices=soc/11230000.mmc printk.devkmsg=on drm_client_lib.active=none mem_sleep_default=s2idle
EOF

# Menu ramdisk. No Android init. fbdev stays enabled so /dev/fb0 exists.
# ttynull keeps fbcon off that framebuffer; drm_client_lib.active=none
# would remove fb0 entirely. evdev.ko is what creates /dev/input/event*.
mkdir -p "$work/menu/lib/modules/6.18.28-mt81-kukui2"
cp "$MENU" "$work/menu/init"
chmod 755 "$work/menu/init"
for ko in evdev.ko hid-multitouch.ko hid-generic.ko i2c-hid.ko i2c-hid-of.ko i2c-hid-of-goodix.ko; do
    cp "$MOD/$ko" "$work/menu/lib/modules/6.18.28-mt81-kukui2/$ko"
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
            description = "mt8183-kukui-krane-sku176";
            data = /incbin/("krane.dtb");
            type = "flat_dt";
            arch = "arm64";
            compression = "none";
            hash-1 { algo = "crc32"; };
        };
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
            description = "mt8183-kukui-krane-sku176";
            kernel = "kernel-1";
            fdt = "fdt-1";
            ramdisk = "ramdisk-1";
            loadables = "kernel-1";
        };
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

mkdir -p "$OUT/android" "$OUT/linux"
cp "$work/Image" "$OUT/android/Image"
cp "$work/krane.dtb" "$OUT/android/krane.dtb"
# kexec does not expand kern_guid=%U. The rest matches the eMMC FIT.
sed 's/^kern_guid=%U //' "$work/android-cmd.txt" > "$OUT/android/cmdline"

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
rm -f "$pmos" "$fit"

echo "android.kpart $(stat -c %s "$OUT/android.kpart") $(sha256sum "$OUT/android.kpart" | awk '{print $1}')"
echo "menu.kpart $(stat -c %s "$OUT/menu.kpart") $(sha256sum "$OUT/menu.kpart" | awk '{print $1}')"
futility dump_kernel_config "$OUT/android.kpart"
echo "--- menu ---"
futility dump_kernel_config "$OUT/menu.kpart"
