#!/bin/bash
# Add a Kodama sku16 configuration to a FIT that already has Krane sku176
# and sku0. The kernel, both Krane DTBs, ramdisk and command line are
# copied unchanged. depthcharge matches the DTB compatible, so Kodama
# boots conf-3 and Krane still boots conf-1 or conf-2.
# Does not write a disk.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${1:?need a kpart with krane sku176 and sku0}"
DEST="${2:?need an output path}"
DTB="${KODAMA_DTB:?set KODAMA_DTB to mt8183-kukui-kodama-sku16.dtb}"
DEVKEYS=/usr/share/vboot/devkeys

[[ -f "$SRC" && -f "$DTB" ]] || { echo "missing input" >&2; exit 1; }
command -v fdtget >/dev/null || { echo "fdtget is required" >&2; exit 1; }
[[ "$(fdtget "$DTB" / compatible)" == "google,kodama-sku16 google,kodama mediatek,mt8183" ]] || {
    echo "$DTB compatible is not kodama sku16" >&2
    exit 1
}
text=$(dtc -I dtb -O dts "$DTB" 2>/dev/null || true)
grep -q -F -- 'auo,b101uan08.3' <<<"$text" || {
    echo "$DTB panel is not auo,b101uan08.3" >&2
    exit 1
}

work=$(mktemp -d /tmp/kukui-kodama.XXXXXX)
trap 'rm -rf "$work"' EXIT
futility vbutil_kernel --get-vmlinuz "$SRC" --vmlinuz-out "$work/fit"
python3 - "$work/fit" "$work" << 'PY'
import subprocess, sys
fit, dest = sys.argv[1:]
listing = subprocess.check_output(["dumpimage", "-l", fit], text=True)
idx = desc = kind = None
items = []
for line in listing.splitlines():
    if line.startswith(" Image "):
        if idx is not None:
            items.append((idx, kind or "", desc or ""))
        idx = line.split()[1].strip("()")
        desc = kind = None
    elif "Description:" in line and idx is not None:
        desc = line.split("Description:", 1)[1].strip()
    elif line.strip().startswith("Type:") and idx is not None:
        kind = line.split("Type:", 1)[1].strip()
if idx is not None:
    items.append((idx, kind or "", desc or ""))
wanted = {
    "Kernel Image (no loading done)": "kernel.lzma",
    "mt8183-kukui-krane-sku176": "krane.dtb",
    "mt8183-kukui-krane-sku0": "krane-sku0.dtb",
}
found = {}
for idx, kind, desc in items:
    if desc == "mt8183-kukui-kodama-sku16":
        sys.exit("FIT already has kodama sku16")
    name = None
    if kind.startswith("Kernel Image"):
        name = "kernel.lzma"
    elif kind.startswith("RAMDisk"):
        name = "ramdisk"
    elif desc in wanted:
        name = wanted[desc]
    if name is None:
        continue
    if name in found:
        sys.exit(f"FIT has more than one {name}")
    found[name] = idx
for name in ("kernel.lzma", "krane.dtb", "krane-sku0.dtb", "ramdisk"):
    if name not in found:
        sys.exit(f"FIT is missing {name}")
for name, idx in found.items():
    subprocess.check_call(["dumpimage", "-T", "flat_dt", "-p", idx, "-o", f"{dest}/{name}", fit])
PY
cp "$DTB" "$work/kodama.dtb"
futility dump_kernel_config "$SRC" > "$work/cmdline.txt"

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
        fdt-3 {
            description = "mt8183-kukui-kodama-sku16";
            data = /incbin/("kodama.dtb");
            type = "flat_dt";
            arch = "arm64";
            compression = "none";
            hash-1 { algo = "crc32"; };
        };
        ramdisk-1 {
            description = "unavailable";
            data = /incbin/("ramdisk");
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
        conf-3 {
            description = "mt8183-kukui-kodama-sku16";
            kernel = "kernel-1";
            fdt = "fdt-3";
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
[[ "$bytes" -le $((32 * 1024 * 1024)) ]] || { echo "$DEST does not fit in 32 MiB" >&2; exit 1; }
echo "$(basename "$DEST") $bytes $(sha256sum "$DEST" | awk '{print $1}')"
futility dump_kernel_config "$DEST"
