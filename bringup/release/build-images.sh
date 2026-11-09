#!/bin/bash
# Assemble the four USB-install images and MANIFEST.
# Does not write a disk and does not call the bringup writers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:?need an output directory}"
SUPER_SRC="${2:-${SUPER:-$ROOT/work/phase4/super.install.raw}}"
USB_KPART="${USB_KPART:-$ROOT/work/phase4/kernel.kpart.usb}"
ANDROID_KPART="${ANDROID_KPART:-$ROOT/work/phase4/install-payload/android.kpart}"
MENU_KPART="${MENU_KPART:-$ROOT/work/phase4/install-payload/menu.kpart}"
SIMG2IMG="${SIMG2IMG:-simg2img}"
SUPER_BYTES=8589934592

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

cmdline_of() {
    futility dump_kernel_config "$1"
}

require_token() {
    local file="$1"
    local token="$2"
    local cfg
    cfg="$(cmdline_of "$file")"
    grep -q -F -- "$token" <<<"$cfg" || {
        echo "$file cmdline missing $token" >&2
        echo "$cfg" >&2
        exit 1
    }
}

# A Krane FIT carries both Krane panels and Kodama sku16. depthcharge
# picks the configuration whose DTB compatible matches the board. A FIT
# with neither Krane name is a single-board image and is not checked.
require_skus() {
    local fit listed name
    fit=$(mktemp)
    futility vbutil_kernel --get-vmlinuz "$1" --vmlinuz-out "$fit"
    listed=$(dumpimage -l "$fit")
    if ! grep -q 'mt8183-kukui-krane-' <<<"$listed"; then
        rm -f "$fit"
        return 0
    fi
    for name in mt8183-kukui-krane-sku176 mt8183-kukui-krane-sku0 mt8183-kukui-kodama-sku16; do
        grep -q "${name}\$" <<<"$listed" || {
            echo "$1 has no $name configuration" >&2
            rm -f "$fit"
            exit 1
        }
    done
    rm -f "$fit"
}

for f in "$USB_KPART" "$ANDROID_KPART" "$MENU_KPART" "$SUPER_SRC"; do
    [[ -f "$f" ]] || { echo "missing $f" >&2; exit 1; }
done
futility vbutil_kernel --verify "$USB_KPART" >/dev/null
futility vbutil_kernel --verify "$ANDROID_KPART" >/dev/null
futility vbutil_kernel --verify "$MENU_KPART" >/dev/null
require_token "$USB_KPART" "androidboot.boot_devices=soc/11201000.usb/11200000.usb"
require_token "$ANDROID_KPART" "androidboot.boot_devices=soc/11230000.mmc"
require_token "$MENU_KPART" "console=ttynull"
require_skus "$USB_KPART"
require_skus "$ANDROID_KPART"
require_skus "$MENU_KPART"
if cmdline_of "$ANDROID_KPART" | grep -q -F 'androidboot.boot_devices=11230000.mmc'; then
    echo "android.kpart boot_devices is missing the soc/ prefix" >&2
    exit 1
fi

cp -a --reflink=auto "$USB_KPART" "$OUT/kernel.kpart"
cp -a --reflink=auto "$ANDROID_KPART" "$OUT/android.kpart"
cp -a --reflink=auto "$MENU_KPART" "$OUT/menu.kpart"

magic="$(od -An -tx1 -N4 "$SUPER_SRC" | tr -d ' \n')"
if [[ "$magic" == "3aff26ed" ]]; then
    command -v "$SIMG2IMG" >/dev/null || { echo "sparse super needs simg2img" >&2; exit 1; }
    "$SIMG2IMG" "$SUPER_SRC" "$OUT/super.img"
else
    cp -a --reflink=auto "$SUPER_SRC" "$OUT/super.img"
fi
got="$(stat -c %s "$OUT/super.img")"
[[ "$got" -eq "$SUPER_BYTES" ]] || {
    echo "super.img is $got bytes, want $SUPER_BYTES" >&2
    exit 1
}

# name, size, sha256. Then the two cmdline checks flash-usb.sh repeats.
{
    for name in kernel.kpart android.kpart menu.kpart super.img; do
        printf '%s %s %s\n' "$name" "$(stat -c %s "$OUT/$name")" "$(sha256sum "$OUT/$name" | awk '{print $1}')"
    done
    printf 'cmdline kernel.kpart androidboot.boot_devices=soc/11201000.usb/11200000.usb\n'
    printf 'cmdline android.kpart androidboot.boot_devices=soc/11230000.mmc\n'
} > "$OUT/MANIFEST"

echo "images in $OUT"
cat "$OUT/MANIFEST"
