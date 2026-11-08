#!/bin/bash
# Derive the Krane sku0 DTB from the sku176 DTB in a FIT.
#
# Upstream mt8183-kukui-krane-sku0.dts and -sku176.dts include the same
# mt8183-kukui-krane.dtsi and differ only in the root compatible/model and
# the DSI panel: sku0 has an AUO kd101n80-45na, sku176 a BOE tv101wum-nl6.
# Both are handled by panel-boe-tv101wum-nl6. coreboot builds the SKU as
# (camera id << 8) | (LCM id << 4) | board strap, so on Krane the SKU is
# the panel. Without a sku0 entry in the FIT, depthcharge falls back to
# "google,krane", boots the sku176 DTB, and the AUO panel stays black.
#
# Editing the extracted DTB keeps the camera nodes and anything else that
# was added to the sku176 DTB in the FIT.
set -euo pipefail

SRC="${1:?need the sku176 dtb}"
DEST="${2:?need an output path}"
PANEL=/soc/dsi@14014000/panel@0

[[ "$(fdtget "$SRC" / compatible)" == "google,krane-sku176 google,krane mediatek,mt8183" ]] || {
    echo "$SRC is not the krane sku176 dtb" >&2; exit 1; }
[[ "$(fdtget "$SRC" "$PANEL" compatible)" == "boe,tv101wum-nl6" ]] || {
    echo "$SRC panel is not boe,tv101wum-nl6" >&2; exit 1; }

cp "$SRC" "$DEST"
fdtput -t s "$DEST" / compatible google,krane-sku0 google,krane mediatek,mt8183
fdtput -t s "$DEST" / model "MediaTek krane sku0 board"
fdtput -t s "$DEST" "$PANEL" compatible auo,kd101n80-45na
