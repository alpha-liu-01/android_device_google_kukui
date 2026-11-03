#!/bin/bash
# Pin ReSukiSU v4.2.0-rc3 into the 6.18.28 tree and apply the manual hooks.
# The version code is 30000 + git commit count + 700. A full clone of this
# tag has 4471 commits, which is the 35171 the arm64 manager APK was built with.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KERNEL="${1:-$ROOT/work/phase2/linux-6.18.28}"
TAG=v4.2.0-rc3
SRC="$KERNEL/KernelSU"

if [[ ! -d "$KERNEL/fs" ]]; then
    echo "not a kernel tree: $KERNEL" >&2
    exit 1
fi

if [[ ! -d "$SRC/.git" ]]; then
    git clone --branch "$TAG" https://github.com/Baka-SU/BakaSU.git "$SRC"
fi
git -C "$SRC" checkout --detach "$TAG"
count="$(git -C "$SRC" rev-list --count HEAD)"
echo "BakaSU $TAG commit count $count (expected 4471, version 35171)"

ln -sfn ../KernelSU/kernel "$KERNEL/drivers/kernelsu"

if ! grep -q ksu_handle_execveat "$KERNEL/fs/exec.c"; then
    patch -d "$KERNEL" -p1 < "$ROOT/bringup/kernel/0001-resukisu-manual-hooks.patch"
fi

if ! grep -q crown_system_manager "$SRC/kernel/manager/throne_tracker.c"; then
    patch -d "$SRC" -p1 < "$ROOT/bringup/kernel/0002-resukisu-system-manager.patch"
fi

echo "hooks present; merge bringup/kernel/resukisu.fragment into .config before building"
