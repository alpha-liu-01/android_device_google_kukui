#!/usr/bin/env python3
"""Add the eMMC installer to a copy of super.cam.raw.

The camera files already in that super stay. The new vendor image has to
fit the existing vendor extent. Nothing here writes a USB stick.
"""
import os
import shutil
import stat
import subprocess
import sys

HOST = "/run/media/alpha/YMTC/lineage-23.2/out/host/linux-x86/bin"
TREE = "/tmp/kukui-img/tree-v"
DEV = "/home/alpha/Documents/GitHub/android_device_google_kukui/device/google/kukui"
APK = "/run/media/alpha/YMTC/lineage-23.2/out/target/product/kukui/vendor/app/KukuiInstall/KukuiInstall.apk"
SUPER_SRC = "/home/alpha/Documents/GitHub/android_device_google_kukui/work/phase4/super.cam.raw"
SUPER_DST = "/home/alpha/Documents/GitHub/android_device_google_kukui/work/phase4/super.install.raw"
IMAGE = "/tmp/kukui-img/vendor.install.img"
VENDOR_OFF = 1148928 * 512
VENDOR_LIMIT = 241464 * 512

HAL = "90952c517b06e12979b4efd2838e7daca6395a22b1ade37baecfea67a3d55e1d"


def ere(path):
    return "".join("\\" + ch if ch in ".+?*|()[]{}^$\\" else ch for ch in path) + "$"


def xset(path, label):
    os.setxattr(path, "security.selinux", label.encode() + b"\x00")


def put(rel, src, mode, uid, gid, label):
    dst = os.path.join(TREE, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)
    os.chmod(dst, mode)
    os.chown(dst, uid, gid)
    xset(dst, label)
    print("added", rel, os.path.getsize(dst))


def label_dir(rel, label):
    path = os.path.join(TREE, rel)
    os.chmod(path, 0o755)
    os.chown(path, 0, 0)
    xset(path, label)


def walk(root):
    entries = []

    def rec(path):
        st = os.lstat(path)
        rel = os.path.relpath(path, root)
        if rel == ".":
            rel = ""
        try:
            label = os.getxattr(path, "security.selinux", follow_symlinks=False)
        except OSError:
            label = b""
        label = label.split(b"\x00", 1)[0].decode()
        entries.append((rel, st.st_uid, st.st_gid, stat.S_IMODE(st.st_mode), label))
        if stat.S_ISDIR(st.st_mode) and not stat.S_ISLNK(st.st_mode):
            for name in sorted(os.listdir(path)):
                rec(os.path.join(path, name))

    rec(root)
    return entries


def main():
    if os.geteuid() != 0:
        sys.exit("need root")
    import hashlib
    hal = os.path.join(TREE, "lib64/hw/camera.libcamera.so")
    digest = hashlib.sha256(open(hal, "rb").read()).hexdigest()
    if digest != HAL:
        sys.exit(f"vendor tree HAL is {digest}")

    put("bin/kukui-installd", f"{DEV}/installer/kukui-installd.sh",
        0o755, 0, 2000, "u:object_r:vendor_file:s0")
    put("etc/init/kukui-install.rc", f"{DEV}/installer/kukui-install.rc",
        0o644, 0, 0, "u:object_r:vendor_configs_file:s0")
    os.makedirs(os.path.join(TREE, "app/KukuiInstall"), exist_ok=True)
    label_dir("app", "u:object_r:vendor_app_file:s0")
    label_dir("app/KukuiInstall", "u:object_r:vendor_app_file:s0")
    put("app/KukuiInstall/KukuiInstall.apk", APK,
        0o644, 0, 0, "u:object_r:vendor_app_file:s0")
    proxy = os.path.join(TREE, "bin/libcamera/soft_ipa_proxy")
    os.chmod(proxy, 0o755)
    print("proxy mode", oct(os.stat(proxy).st_mode))
    # The vendor tree still had the CPU debayer config. The device tree
    # selects the GLES ISP that the camera bring-up actually ran.
    put("etc/libcamera/configuration.yaml",
        f"{DEV}/etc/libcamera/configuration.yaml",
        0o644, 0, 0, "u:object_r:vendor_configs_file:s0")

    rows = walk(TREE)
    with open("/tmp/kukui-img/vendor_fs", "w") as fs, open("/tmp/kukui-img/vendor_ctx", "w") as ctx:
        for rel, uid, gid, mode, label in rows:
            shown = "/" if rel == "" else rel
            canned = shown if rel == "" else f"vendor/{rel}"
            fs.write(f"{canned} {uid} {gid} {mode:04o}\n")
            full = "/vendor" if rel == "" else f"/vendor/{rel}"
            if label:
                ctx.write(f"{ere(full)} {label}\n")
    print("entries", len(rows))

    if os.path.exists(IMAGE):
        os.remove(IMAGE)
    subprocess.check_call([
        f"{HOST}/mkfs.erofs",
        "-z", "lz4hc,9",
        "-b", "4096",
        "-T", "1762042398",
        "--mount-point", "vendor",
        "--fs-config-file", "/tmp/kukui-img/vendor_fs",
        "--file-contexts", "/tmp/kukui-img/vendor_ctx",
        "--preserve-mtime",
        IMAGE,
        TREE,
    ])
    size = os.path.getsize(IMAGE)
    print("vendor image", size, "limit", VENDOR_LIMIT)
    if size > VENDOR_LIMIT:
        sys.exit("vendor image does not fit the existing extent")

    print("copy super")
    shutil.copyfile(SUPER_SRC, SUPER_DST)
    blob = open(IMAGE, "rb").read()
    with open(SUPER_DST, "r+b") as out:
        out.seek(VENDOR_OFF)
        out.write(blob)
        if len(blob) < VENDOR_LIMIT:
            out.write(b"\x00" * (VENDOR_LIMIT - len(blob)))
    os.chmod(SUPER_DST, 0o644)
    if os.path.getsize(SUPER_DST) != 8589934592:
        sys.exit("super size changed")
    print("SUPER_OK", os.path.getsize(SUPER_DST))


if __name__ == "__main__":
    main()
