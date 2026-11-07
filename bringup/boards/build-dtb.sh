#!/bin/bash
# Build a Kukui board DTB from a Linux 6.18.28 source tree.
#
# Required:
#   LINUX_SRC   Path to a linux-6.18.28 source tree.
#
# Optional:
#   DTS         DTS file to build. Defaults to Kodama sku16.
#   KUKUI_COMPAT Compatible string that must be present in the DTB.
#                Defaults to "google," so any Kukui DTB is accepted.
#
# Usage:
#   LINUX_SRC=/path/to/linux-6.18.28 \
#     bringup/boards/build-dtb.sh /path/to/output
set -euo pipefail

LINUX_SRC="${LINUX_SRC:?set LINUX_SRC to a linux-6.18.28 source tree}"
OUT="${1:?need an output directory}"
DTS="${DTS:-$LINUX_SRC/arch/arm64/boot/dts/mediatek/mt8183-kukui-kodama-sku16.dts}"
COMPAT="${KUKUI_COMPAT:-google,}"

[[ -f "$DTS" ]] || { echo "missing DTS: $DTS" >&2; exit 1; }
command -v cpp >/dev/null || { echo "cpp is required" >&2; exit 1; }
command -v dtc >/dev/null || { echo "dtc is required" >&2; exit 1; }

mkdir -p "$OUT"
work=$(mktemp -d /tmp/kukui-dtb.XXXXXX)
trap 'rm -rf "$work"' EXIT

name="$(basename "$DTS" .dts)"
cpp -nostdinc \
    -I "$LINUX_SRC/include" \
    -I "$LINUX_SRC/arch/arm64/boot/dts" \
    -I "$LINUX_SRC/arch/arm64/boot/dts/mediatek" \
    -I "$LINUX_SRC/scripts/dtc/include-prefixes" \
    -undef -D__DTS__ -x assembler-with-cpp \
    -o "$work/$name.dts" "$DTS"
dtc -I dts -O dtb -o "$OUT/$name.dtb" "$work/$name.dts"

if ! dtc -I dtb -O dts "$OUT/$name.dtb" 2>/dev/null | grep -q -F "$COMPAT"; then
    echo "$OUT/$name.dtb does not contain $COMPAT" >&2
    exit 1
fi
if ! dtc -I dtb -O dts "$OUT/$name.dtb" 2>/dev/null | grep -q -F 'mediatek,mt8183'; then
    echo "$OUT/$name.dtb does not contain mediatek,mt8183" >&2
    exit 1
fi

echo "$OUT/$name.dtb $(stat -c %s "$OUT/$name.dtb") $(sha256sum "$OUT/$name.dtb" | awk '{print $1}')"
