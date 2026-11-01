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
#   memfd, codec2 IConfigurable, mesa 25 board.mk, v4l2 seccomp
#     machine-independent fixes this product boots with. --reverse leaves
#     them in place.
#   system_cros_codecs_mm21_nv12.patch
#     the stateless decoder writes MM21 into its own buffers, then copies
#     linear NV12 into the caller's buffer. A decoded frame stays queued
#     until that buffer exists. Flush drops the queued picture instead of
#     copying it. --reverse removes it so a Gru build keeps the zero-copy path.
#   system_cros_codecs_v4l2_flush_reset.patch
#     a same-format seek streams the V4L2 queues off and the next SPS starts
#     a new sequence. VAAPI keeps the old flush path. --reverse removes it.
#   external_v4l2r_cached_capture.patch
#   system_cros_codecs_v4l2_cached_capture.patch
#     the decoder capture queue asks for cached MMAP buffers. DQBUF still
#     invalidates them. --reverse removes both.
#   system_cros_codecs_v4l2_poll_wait.patch
#     wait for a capture or output buffer with poll instead of a doubling
#     sleep. --reverse removes it.
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
    if patch -d "${LINEAGE_ROOT}/system/cros-codecs" -p1 -R --dry-run -s \
        < "${REPO_ROOT}/patches/system_cros_codecs_mm21_nv12.patch" >/dev/null 2>&1; then
        patch -d "${LINEAGE_ROOT}/system/cros-codecs" -p1 -R \
            < "${REPO_ROOT}/patches/system_cros_codecs_mm21_nv12.patch" >/dev/null
        echo "[OK]    removed MM21 to NV12 decoder copy"
    else
        echo "[SKIP]  MM21 to NV12 decoder copy is not applied"
    fi
    if patch -d "${LINEAGE_ROOT}/system/cros-codecs" -p1 -R --dry-run -s \
        < "${REPO_ROOT}/patches/system_cros_codecs_v4l2_flush_reset.patch" >/dev/null 2>&1; then
        patch -d "${LINEAGE_ROOT}/system/cros-codecs" -p1 -R \
            < "${REPO_ROOT}/patches/system_cros_codecs_v4l2_flush_reset.patch" >/dev/null
        echo "[OK]    removed V4L2 flush reset"
    else
        echo "[SKIP]  V4L2 flush reset is not applied"
    fi
    if patch -d "${LINEAGE_ROOT}/system/cros-codecs" -p1 -R --dry-run -s \
        < "${REPO_ROOT}/patches/system_cros_codecs_v4l2_cached_capture.patch" >/dev/null 2>&1; then
        patch -d "${LINEAGE_ROOT}/system/cros-codecs" -p1 -R \
            < "${REPO_ROOT}/patches/system_cros_codecs_v4l2_cached_capture.patch" >/dev/null
        echo "[OK]    removed cached capture buffers"
    else
        echo "[SKIP]  cached capture buffers are not applied"
    fi
    if patch -d "${LINEAGE_ROOT}/external/rust/crates/v4l2r" -p1 -R --dry-run -s \
        < "${REPO_ROOT}/patches/external_v4l2r_cached_capture.patch" >/dev/null 2>&1; then
        patch -d "${LINEAGE_ROOT}/external/rust/crates/v4l2r" -p1 -R \
            < "${REPO_ROOT}/patches/external_v4l2r_cached_capture.patch" >/dev/null
        echo "[OK]    removed v4l2r cached capture request"
    else
        echo "[SKIP]  v4l2r cached capture request is not applied"
    fi
    if patch -d "${LINEAGE_ROOT}/system/cros-codecs" -p1 -R --dry-run -s \
        < "${REPO_ROOT}/patches/system_cros_codecs_v4l2_poll_wait.patch" >/dev/null 2>&1; then
        patch -d "${LINEAGE_ROOT}/system/cros-codecs" -p1 -R \
            < "${REPO_ROOT}/patches/system_cros_codecs_v4l2_poll_wait.patch" >/dev/null
        echo "[OK]    removed V4L2 poll wait"
    else
        echo "[SKIP]  V4L2 poll wait is not applied"
    fi
    exit 0
fi

link_device_tree
install_manifest
apply_audio
apply_or_skip "${LINEAGE_ROOT}/system/core" \
    "${REPO_ROOT}/patches/system_core_libcutils_memfd_isolated_app.patch" \
    "memfd isolated-app"
apply_or_skip "${LINEAGE_ROOT}/frameworks/av" \
    "${REPO_ROOT}/patches/frameworks_av_codec2_ion_fallback.patch" \
    "codec2 IConfigurable"
apply_or_skip "${LINEAGE_ROOT}/device/mainline/common" \
    "${REPO_ROOT}/patches/device_mainline_common_mesa_board_mk.patch" \
    "mesa 25 board.mk"
apply_or_skip "${LINEAGE_ROOT}/device/mainline/common" \
    "${REPO_ROOT}/patches/device_mainline_common_v4l2_codec2_seccomp.patch" \
    "v4l2 codec2 seccomp"
apply_or_skip "${LINEAGE_ROOT}/system/cros-codecs" \
    "${REPO_ROOT}/patches/system_cros_codecs_mm21_nv12.patch" \
    "MM21 to NV12 decoder copy"
apply_or_skip "${LINEAGE_ROOT}/system/cros-codecs" \
    "${REPO_ROOT}/patches/system_cros_codecs_v4l2_flush_reset.patch" \
    "V4L2 flush reset"
apply_or_skip "${LINEAGE_ROOT}/external/rust/crates/v4l2r" \
    "${REPO_ROOT}/patches/external_v4l2r_cached_capture.patch" \
    "v4l2r cached capture request"
apply_or_skip "${LINEAGE_ROOT}/system/cros-codecs" \
    "${REPO_ROOT}/patches/system_cros_codecs_v4l2_cached_capture.patch" \
    "cached capture buffers"
apply_or_skip "${LINEAGE_ROOT}/system/cros-codecs" \
    "${REPO_ROOT}/patches/system_cros_codecs_v4l2_poll_wait.patch" \
    "V4L2 poll wait"
