#!/usr/bin/env bash
# Prepare a LineageOS 23.2 tree to build Kukui.
#
# Does not read device/google/gru and does not apply Gru's rockchip,
# DA7219, camera, or sepolicy patches.
#
#   patches/apply-patches.sh /path/to/lineage-23.2
#   patches/apply-patches.sh --reverse /path/to/lineage-23.2
#
# Forward links device/google/kukui into the tree (Soong does not follow a
# directory symlink; each file is linked, and a directory that contains
# Android.bp stays a real directory). It installs local_manifests/kukui.xml
# when those projects are not already declared, then applies:
#
#   hardware_interfaces_audio_kukui_standalone.patch
#     clean hardware/interfaces. USB blocking I/O, mic gain, Kukui card
#     lookup, speaker blocking writes, USB playback keepalive, A2DP standby.
#   hardware_interfaces_audio_kukui.patch
#     only when Gru's audio patches are already applied. The Kukui branches
#     run when ro.vendor.audio.route=kukui; otherwise that tree's DA7219
#     path stays. Reverse this one before building Gru.
#   memfd, codec2 IConfigurable, mesa 25 board.mk, v4l2 seccomp,
#   vendor_available on libexif/libhwy/skcms, brightness property,
#   settings and netlink null checks
#     shared fixes. The brightness switch defaults off. --reverse leaves
#     these in place.
#   system_cros_codecs.patch, external_v4l2r.patch, external_v4l2_codec2.patch
#     stateless H.264 on mtk-vcodec. MM21 is copied to linear NV12.
#     --reverse removes them so a Gru build keeps its own decoder path.
#   system_cros_codecs_mdp3.patch
#     MDP3 converts MM21 to NV12 instead of the CPU, straight from the
#     decoder buffers into the client buffer. The CPU copy stays as the
#     fallback when there is no mtk-mdp3 node or vendor.cros_codecs.mdp3=0.
#     Goes on top of system_cros_codecs.patch; --reverse removes it first.
#   external_mesa_panvk_host_cached.patch
#     a second Vulkan memory type with HOST_CACHED. Type 0 stays the old
#     coherent mapping. --reverse leaves it.
#   external_drm_hwcomposer_dsi_crtc.patch
#     DSI prefers the CRTC with more planes. The property defaults on,
#     which is the RK3399 big VOP. Krane has one DSI CRTC.
#   external_drm_hwcomposer_mdp3_rotation.patch
#     90/270 degree layers (Firefox content) are rotated by MediaTek MDP3
#     one frame ahead and put on a plane, instead of being drawn by the
#     GPU. Needs mtk-mdp3.ko and bringup/kernel/mtk-mdp3-mt8183-scp-abi.patch.
#     Without an mtk-mdp3 node, or with vendor.hwc.drm.mdp3_rotation=0,
#     those layers go to the GPU as before.
#   frameworks_base_hwui_gl_prerotation.patch
#     HWUI's GL pipeline follows the window transform hint the way the
#     Vulkan one does: buffers in panel orientation, drawn through a
#     pre-rotation matrix, one extra buffer while planes hold the last
#     one. Off unless debug.hwui.gl_prerotation is set; init.kukui.rc
#     sets it. --reverse leaves it.
#   frameworks_base_lid_wake.patch
#     With the lid closed and lid_behavior sleep, motion events (the
#     keyboard cover's touchpad) and keys other than power and wakeup do
#     not wake the screen. The cover's touchpad faces the closed screen
#     and counts as an external device, which may wake on any motion.
#     --reverse leaves it; without a closed lid it changes nothing.
#   external_minigbm*.patch
#     NV12 decoder stride and an HWC fallback that drops scanout when the
#     display cannot take the format. The Rockchip AFBC dumb backend is
#     not included.
#   system_core healthd and the boot-device filter
#     healthd accepts the Krane supply nodes. The boot-device filter only
#     skips a partition when androidboot.boot_devices is set. --reverse
#     removes the healthd fallbacks and leaves the filter.
#   system_sepolicy_mainline.patch
#     devtmpfs nodes and sysfs inodes that never get a genfs label.
#     --reverse leaves it. Both mainline products need it to compile
#     enforcing policy.
#
# external/libcamera in a tree that was also used for Gru may contain an
# rkisp1 pipeline. This script does not apply it. Kukui installs the
# prebuilt camera HAL from device/google/kukui/camera/prebuilt.
#
# A Kukui build refuses to start while KukuiMixer.h is absent.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REVERSE=0
if [[ "${1:-}" == "--reverse" ]]; then
    REVERSE=1
    shift
fi
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [--reverse] <lineage-23.2-root>" >&2
    exit 1
fi
LINEAGE_ROOT="$(cd "$1" && pwd)"

apply_or_skip() {
    local dir="$1"
    local patch="$2"
    local label="$3"
    if [[ ! -d "$dir" ]]; then
        echo "[FAIL]  missing ${dir}" >&2
        echo "        install local_manifests/kukui.xml and run repo sync" >&2
        return 1
    fi
    if patch -d "$dir" -p1 -R --dry-run -s < "$patch" >/dev/null 2>&1; then
        echo "[SKIP]  ${label} already applied"
    elif patch -d "$dir" -p1 --dry-run -s < "$patch" >/dev/null 2>&1; then
        patch -d "$dir" -p1 < "$patch" >/dev/null
        echo "[OK]    ${label}"
    else
        echo "[FAIL]  ${label} does not apply to ${dir}" >&2
        return 1
    fi
}

audio_state() {
    # Prints applied-standalone, applied-overlay, or absent.
    local target="${LINEAGE_ROOT}/hardware/interfaces"
    local standalone="${REPO_ROOT}/patches/hardware_interfaces_audio_kukui_standalone.patch"
    local overlay="${REPO_ROOT}/patches/hardware_interfaces_audio_kukui.patch"
    if patch -d "$target" -p1 -R --dry-run -s < "$standalone" >/dev/null 2>&1; then
        echo applied-standalone
    elif patch -d "$target" -p1 -R --dry-run -s < "$overlay" >/dev/null 2>&1; then
        echo applied-overlay
    else
        echo absent
    fi
}

apply_audio() {
    local target="${LINEAGE_ROOT}/hardware/interfaces"
    local standalone="${REPO_ROOT}/patches/hardware_interfaces_audio_kukui_standalone.patch"
    local overlay="${REPO_ROOT}/patches/hardware_interfaces_audio_kukui.patch"
    [[ -d "$target" ]] || { echo "[FAIL]  missing ${target}" >&2; return 1; }
    local state
    state="$(audio_state)"
    if [[ "$state" != absent ]]; then
        echo "[SKIP]  Kukui audio patch already applied (${state})"
        return 0
    fi
    if patch -d "$target" -p1 --dry-run -s < "$standalone" >/dev/null 2>&1; then
        patch -d "$target" -p1 < "$standalone" >/dev/null
        echo "[OK]    Kukui audio patch (standalone) -> ${target}"
    elif patch -d "$target" -p1 --dry-run -s < "$overlay" >/dev/null 2>&1; then
        patch -d "$target" -p1 < "$overlay" >/dev/null
        echo "[OK]    Kukui audio patch (on an already patched audio HAL) -> ${target}"
        echo "        reverse it before building Gru"
    else
        echo "[FAIL]  Kukui audio patch does not apply to ${target}" >&2
        return 1
    fi
}

reverse_or_skip() {
    local dir="$1"
    local patch="$2"
    local label="$3"
    if [[ ! -d "$dir" ]]; then
        echo "[FAIL]  missing ${dir}" >&2
        return 1
    fi
    if patch -d "$dir" -p1 -R --dry-run -s < "$patch" >/dev/null 2>&1; then
        patch -d "$dir" -p1 -R < "$patch" >/dev/null
        echo "[OK]    removed ${label}"
    else
        echo "[SKIP]  ${label} is not applied"
    fi
}

reverse_audio() {
    local target="${LINEAGE_ROOT}/hardware/interfaces"
    local standalone="${REPO_ROOT}/patches/hardware_interfaces_audio_kukui_standalone.patch"
    local overlay="${REPO_ROOT}/patches/hardware_interfaces_audio_kukui.patch"
    [[ -d "$target" ]] || { echo "[FAIL]  missing ${target}" >&2; return 1; }
    local state
    state="$(audio_state)"
    case "$state" in
        applied-standalone)
            patch -d "$target" -p1 -R < "$standalone" >/dev/null
            echo "[OK]    removed standalone Kukui audio patch"
            ;;
        applied-overlay)
            patch -d "$target" -p1 -R < "$overlay" >/dev/null
            echo "[OK]    removed Kukui audio patch"
            ;;
        absent)
            if patch -d "$target" -p1 --dry-run -s < "$standalone" >/dev/null 2>&1 \
                || patch -d "$target" -p1 --dry-run -s < "$overlay" >/dev/null 2>&1; then
                echo "[SKIP]  Kukui audio patch is not applied"
            else
                echo "[FAIL]  Kukui audio patch does not match ${target}" >&2
                return 1
            fi
            ;;
    esac
}

link_device_tree() {
    local src="${REPO_ROOT}/device/google/kukui"
    local dst="${LINEAGE_ROOT}/device/google/kukui"
    local rel from to
    while IFS= read -r -d '' rel; do
        rel="${rel#./}"
        from="${src}/${rel}"
        to="${dst}/${rel}"
        if [[ -e "$to" || -L "$to" ]]; then
            continue
        fi
        mkdir -p "$(dirname "$to")"
        ln -s "$from" "$to"
        echo "[OK]    link device/google/kukui/${rel}"
    done < <(cd "$src" && find . -type f -print0)
}

install_manifest() {
    local manifests="${LINEAGE_ROOT}/.repo/local_manifests"
    local src="${REPO_ROOT}/local_manifests/kukui.xml"
    if [[ ! -d "${LINEAGE_ROOT}/.repo" ]]; then
        echo "[WARN]  ${LINEAGE_ROOT} has no .repo; copy local_manifests/kukui.xml yourself"
        return 0
    fi
    mkdir -p "$manifests"
    if [[ -f "${manifests}/gru.xml" ]]; then
        echo "[SKIP]  local manifest: gru.xml already lists the mainline projects"
        echo "        do not also install kukui.xml; repo rejects the duplicate paths"
        return 0
    fi
    if [[ -f "${manifests}/kukui.xml" ]] && cmp -s "$src" "${manifests}/kukui.xml"; then
        echo "[SKIP]  local_manifests/kukui.xml already installed"
        return 0
    fi
    cp "$src" "${manifests}/kukui.xml"
    echo "[OK]    local_manifests/kukui.xml"
    echo "        run repo sync before the first build"
}

if [[ $REVERSE -eq 1 ]]; then
    reverse_audio
    reverse_or_skip "${LINEAGE_ROOT}/system/cros-codecs" \
        "${REPO_ROOT}/patches/system_cros_codecs_mdp3.patch" \
        "MDP3 MM21 conversion"
    reverse_or_skip "${LINEAGE_ROOT}/system/cros-codecs" \
        "${REPO_ROOT}/patches/system_cros_codecs.patch" \
        "stateless V4L2 decoder"
    reverse_or_skip "${LINEAGE_ROOT}/external/rust/crates/v4l2r" \
        "${REPO_ROOT}/patches/external_v4l2r.patch" \
        "v4l2r capture queue"
    reverse_or_skip "${LINEAGE_ROOT}/external/v4l2_codec2" \
        "${REPO_ROOT}/patches/external_v4l2_codec2.patch" \
        "v4l2 codec2 stateless HAL"
    reverse_or_skip "${LINEAGE_ROOT}/system/core" \
        "${REPO_ROOT}/patches/system_core_healthd_supply.patch" \
        "healthd supply fallbacks"
    reverse_or_skip "${LINEAGE_ROOT}/frameworks/av" \
        "${REPO_ROOT}/patches/frameworks_av_ccodec_flush_input.patch" \
        "codec2 flush returns input slots"
    exit 0
fi

link_device_tree
install_manifest
apply_audio
apply_or_skip "${LINEAGE_ROOT}/system/core" \
    "${REPO_ROOT}/patches/system_core_libcutils_memfd_isolated_app.patch" \
    "memfd isolated-app"
apply_or_skip "${LINEAGE_ROOT}/system/core" \
    "${REPO_ROOT}/bringup/phase4/init-prefer-boot-device.patch" \
    "boot-device partition filter"
apply_or_skip "${LINEAGE_ROOT}/system/core" \
    "${REPO_ROOT}/patches/system_core_healthd_supply.patch" \
    "healthd supply fallbacks"
apply_or_skip "${LINEAGE_ROOT}/frameworks/av" \
    "${REPO_ROOT}/patches/frameworks_av_codec2_ion_fallback.patch" \
    "codec2 IConfigurable"
apply_or_skip "${LINEAGE_ROOT}/frameworks/av" \
    "${REPO_ROOT}/patches/frameworks_av_ccodec_flush_input.patch" \
    "codec2 flush returns input slots"
apply_or_skip "${LINEAGE_ROOT}/frameworks/base" \
    "${REPO_ROOT}/patches/frameworks_base_brightness_and_media.patch" \
    "brightness property and media null checks"
apply_or_skip "${LINEAGE_ROOT}/frameworks/base" \
    "${REPO_ROOT}/patches/frameworks_base_hwui_gl_prerotation.patch" \
    "HWUI GL pre-rotation"
apply_or_skip "${LINEAGE_ROOT}/frameworks/base" \
    "${REPO_ROOT}/patches/frameworks_base_lid_wake.patch" \
    "no touchpad or key wake with the lid closed"
apply_or_skip "${LINEAGE_ROOT}/device/mainline/common" \
    "${REPO_ROOT}/patches/device_mainline_common_mesa_board_mk.patch" \
    "mesa 25 board.mk"
apply_or_skip "${LINEAGE_ROOT}/device/mainline/common" \
    "${REPO_ROOT}/patches/device_mainline_common_v4l2_codec2_seccomp.patch" \
    "v4l2 codec2 seccomp"
apply_or_skip "${LINEAGE_ROOT}/external/XMP-Toolkit-SDK" \
    "${REPO_ROOT}/patches/external_xmp_vendor_available.patch" \
    "libexif vendor_available"
apply_or_skip "${LINEAGE_ROOT}/external/google-highway" \
    "${REPO_ROOT}/patches/external_google_highway_vendor_available.patch" \
    "libhwy vendor_available"
apply_or_skip "${LINEAGE_ROOT}/external/skia" \
    "${REPO_ROOT}/patches/external_skia_vendor_available.patch" \
    "skcms vendor_available"
apply_or_skip "${LINEAGE_ROOT}/external/drm_hwcomposer" \
    "${REPO_ROOT}/patches/external_drm_hwcomposer_dsi_crtc.patch" \
    "DSI CRTC selection"
apply_or_skip "${LINEAGE_ROOT}/external/drm_hwcomposer" \
    "${REPO_ROOT}/patches/external_drm_hwcomposer_mdp3_rotation.patch" \
    "MDP3 rotation"
apply_or_skip "${LINEAGE_ROOT}/external/mesa" \
    "${REPO_ROOT}/patches/external_mesa_panvk_host_cached.patch" \
    "panvk HOST_CACHED"
apply_or_skip "${LINEAGE_ROOT}/external/minigbm" \
    "${REPO_ROOT}/patches/external_minigbm_nv12.patch" \
    "minigbm NV12"
apply_or_skip "${LINEAGE_ROOT}/external/minigbm-upstream" \
    "${REPO_ROOT}/patches/external_minigbm_upstream_nv12.patch" \
    "minigbm-upstream NV12"
apply_or_skip "${LINEAGE_ROOT}/system/cros-codecs" \
    "${REPO_ROOT}/patches/system_cros_codecs.patch" \
    "stateless V4L2 decoder"
apply_or_skip "${LINEAGE_ROOT}/system/cros-codecs" \
    "${REPO_ROOT}/patches/system_cros_codecs_mdp3.patch" \
    "MDP3 MM21 conversion"
apply_or_skip "${LINEAGE_ROOT}/external/rust/crates/v4l2r" \
    "${REPO_ROOT}/patches/external_v4l2r.patch" \
    "v4l2r capture queue"
apply_or_skip "${LINEAGE_ROOT}/external/v4l2_codec2" \
    "${REPO_ROOT}/patches/external_v4l2_codec2.patch" \
    "v4l2 codec2 stateless HAL"
apply_or_skip "${LINEAGE_ROOT}/packages/apps/Settings" \
    "${REPO_ROOT}/patches/packages_apps_settings_hearing_aid_null.patch" \
    "settings hearing-aid null checks"
apply_or_skip "${LINEAGE_ROOT}/packages/modules/Connectivity" \
    "${REPO_ROOT}/patches/packages_modules_connectivity_netlink.patch" \
    "netlink EINVAL"
apply_or_skip "${LINEAGE_ROOT}/packages/modules/NetworkStack" \
    "${REPO_ROOT}/patches/packages_modules_networkstack_netlink.patch" \
    "netlink monitor restart"
apply_or_skip "${LINEAGE_ROOT}/system/sepolicy" \
    "${REPO_ROOT}/patches/system_sepolicy_mainline.patch" \
    "mainline sepolicy"
