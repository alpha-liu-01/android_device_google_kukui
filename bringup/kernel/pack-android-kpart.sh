#!/bin/bash
# Rebuild the eMMC Android FIT with a new Image and the ramdisk, dtb, and
# command line already in an existing android.kpart. Does not write a disk.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${1:-$ROOT/work/phase4/install-payload/android.kpart}"
IMAGE="${2:-$ROOT/work/phase2/linux-6.18.63/arch/arm64/boot/Image}"
DEST="${3:-$ROOT/work/resukisu/android.kpart}"
DEVKEYS=/usr/share/vboot/devkeys

[[ -f "$SRC" && -f "$IMAGE" ]] || { echo "missing input" >&2; exit 1; }
mkdir -p "$(dirname "$DEST")"
work=$(mktemp -d /tmp/kukui-kpart.XXXXXX)
trap 'rm -rf "$work"' EXIT

fit=$(mktemp)
futility vbutil_kernel --get-vmlinuz "$SRC" --vmlinuz-out "$fit"
dumpimage -T flat_dt -p 1 -o "$work/krane.dtb" "$fit"
dumpimage -T flat_dt -p 2 -o "$work/ramdisk.gz" "$fit"
rm -f "$fit"
test "$(stat -c %s "$work/krane.dtb")" = 65144
# Same DTB with the sku0 panel and compatible. See krane-sku0-dtb.sh.
"$ROOT/bringup/kernel/krane-sku0-dtb.sh" "$work/krane.dtb" "$work/krane-sku0.dtb"
lzma -9 -c "$IMAGE" > "$work/kernel.lzma"
futility dump_kernel_config "$SRC" > "$work/cmdline.txt"
grep -q 'androidboot.boot_devices=soc/11230000.mmc' "$work/cmdline.txt"

cat > "$work/kernel.its" << 'EOF'
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
        fdt-2 {
            description = "mt8183-kukui-krane-sku0";
            data = /incbin/("krane-sku0.dtb");
            type = "flat_dt";
            arch = "arm64";
            compression = "none";
            hash-1 { algo = "crc32"; };
        };
        ramdisk-1 {
            description = "unavailable";
            data = /incbin/("ramdisk.gz");
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
        conf-2 {
            description = "mt8183-kukui-krane-sku0";
            kernel = "kernel-1";
            fdt = "fdt-2";
            ramdisk = "ramdisk-1";
            loadables = "kernel-1";
        };
    };
};
EOF

(cd "$work" && mkimage -D "-I dts -O dtb -p 2048" -f kernel.its image.itb)
dd if=/dev/zero of="$work/bootloader.bin" bs=4096 count=1 status=none
futility vbutil_kernel --pack "$DEST" \
    --keyblock "$DEVKEYS/kernel.keyblock" \
    --signprivate "$DEVKEYS/kernel_data_key.vbprivk" \
    --version 1 \
    --config "$work/cmdline.txt" \
    --bootloader "$work/bootloader.bin" \
    --vmlinuz "$work/image.itb" \
    --arch arm
futility vbutil_kernel --verify "$DEST" >/dev/null
bytes=$(stat -c %s "$DEST")
[[ "$bytes" -le $((32 * 1024 * 1024)) ]] || { echo "android.kpart does not fit in 32 MiB" >&2; exit 1; }
echo "android.kpart $bytes $(sha256sum "$DEST" | awk '{print $1}')"
futility dump_kernel_config "$DEST"
