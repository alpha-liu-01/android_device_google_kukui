#!/bin/bash
# Pack the installer zip. flash-usb.sh stays executable.
#   pack-zip.sh /path/to/images /path/to/kukui-usb-YYYYMMDD.zip
set -euo pipefail

IMAGES="${1:?need the images directory}"
ZIP="${2:?need the zip output path}"
HERE="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$IMAGES/MANIFEST" && -f "$HERE/flash-usb.sh" ]] || {
    echo "need MANIFEST and flash-usb.sh" >&2
    exit 1
}

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp "$HERE/flash-usb.sh" "$stage/flash-usb.sh"
chmod 755 "$stage/flash-usb.sh"
mkdir -p "$stage/images"
cp -a "$IMAGES/MANIFEST" "$IMAGES/kernel.kpart" "$IMAGES/android.kpart" \
    "$IMAGES/menu.kpart" "$IMAGES/super.img" "$stage/images/"
rm -f "$ZIP"
(
    cd "$stage"
    zip -0 -r "$ZIP" flash-usb.sh images
)
python3 - "$ZIP" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
info = z.getinfo("flash-usb.sh")
mode = (info.external_attr >> 16) & 0o777
print(f"flash-usb.sh mode {mode:o}")
if mode & 0o111 == 0:
    sys.exit("flash-usb.sh in the zip is not executable")
names = set(z.namelist())
need = {
    "flash-usb.sh",
    "images/MANIFEST",
    "images/kernel.kpart",
    "images/android.kpart",
    "images/menu.kpart",
    "images/super.img",
}
missing = need - names
if missing:
    sys.exit(f"zip missing {sorted(missing)}")
print("zip", sys.argv[1])
PY
