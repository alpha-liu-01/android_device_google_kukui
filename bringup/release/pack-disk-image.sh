#!/bin/bash
# Build one GPT disk image and a zip Rufus and BalenaEtcher can write.
# The partition layout is the Kukui installer disk, not the Gru SD layout.
#   pack-disk-image.sh /path/to/images /path/to/output-dir
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGES="${1:?need the images directory}"
OUTDIR="${2:?need the output directory}"
HOST_BIN="${HOST_BIN:-/run/media/alpha/YMTC/lineage-23.2/out/host/linux-x86/bin}"
SGDISK="${SGDISK:-$HOST_BIN/sgdisk}"
MKE2FS="${MKE2FS:-$HOST_BIN/mke2fs}"
MAKE_F2FS="${MAKE_F2FS:-$HOST_BIN/make_f2fs}"
DATE_TAG="${DATE_TAG:-$(date +%Y%m%d)}"
NAME="${IMG_BASENAME:-lineage-23.2-kukui-${DATE_TAG}}"

for tool in "$SGDISK" "$MKE2FS" "$MAKE_F2FS"; do
    [[ -x "$tool" ]] || { echo "missing $tool" >&2; exit 1; }
done
[[ -f "$IMAGES/MANIFEST" ]] || { echo "no MANIFEST in $IMAGES" >&2; exit 1; }

mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
IMAGES="$(cd "$IMAGES" && pwd)"
RAW="$OUTDIR/${NAME}.img"
ZIP="$OUTDIR/${NAME}.zip"
SHA="$OUTDIR/${NAME}.zip.sha256"

# Same sectors as flash-usb.sh. userdata is 2450 MiB so the image fits a
# 16 GiB stick. A larger stick keeps this size; the installer only reads
# the kernel slot, pmOS_boot, and the 8 GiB super.
P1_START=8192;       P1_END=73727
P2_START=73728;      P2_END=1122303
P3_START=1122304;    P3_END=17899519
P4_START=17899520;   P4_END=17932287
P5_START=17932288;   P5_END=17940479
P6_START=17940480;   P6_SECTORS=5017600
P6_END=$((P6_START + P6_SECTORS - 1))
TOTAL_SECTORS=$((P6_END + 1 + 4096))
TOTAL_BYTES=$((TOTAL_SECTORS * 512))
ATTR=0x01ff000000000000

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "formatting pmOS_boot and metadata"
mkdir -p "$work/payload/kukui-install"
cp -a "$IMAGES/android.kpart" "$IMAGES/menu.kpart" "$work/payload/kukui-install/"
truncate -s $(((P2_END - P2_START + 1) * 512)) "$work/pmos_boot.img"
"$MKE2FS" -q -F -t ext4 -b 4096 -L pmOS_boot \
    -E lazy_itable_init=0,lazy_journal_init=0 \
    -d "$work/payload" "$work/pmos_boot.img"
truncate -s $(((P4_END - P4_START + 1) * 512)) "$work/metadata.img"
"$MKE2FS" -q -F -t ext4 -b 4096 -L metadata \
    -E lazy_itable_init=0,lazy_journal_init=0 "$work/metadata.img"
truncate -s $((P6_SECTORS * 512)) "$work/userdata.img"
"$MAKE_F2FS" -q -f -O encrypt,extra_attr,project_quota,quota,compression \
    -l userdata "$work/userdata.img" >/dev/null

echo "creating ${TOTAL_BYTES}-byte GPT image"
rm -f "$RAW"
truncate -s "$TOTAL_BYTES" "$RAW"
"$SGDISK" --clear \
    --new="1:${P1_START}:${P1_END}" --change-name=1:pmOS_kernel \
        --typecode=1:FE3A2A5D-4F32-41A7-B725-ACCC3285A309 \
    --new="2:${P2_START}:${P2_END}" --change-name=2:pmOS_boot \
        --typecode=2:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new="3:${P3_START}:${P3_END}" --change-name=3:super \
        --typecode=3:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new="4:${P4_START}:${P4_END}" --change-name=4:metadata \
        --typecode=4:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new="5:${P5_START}:${P5_END}" --change-name=5:misc \
        --typecode=5:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    --new="6:${P6_START}:${P6_END}" --change-name=6:userdata \
        --typecode=6:0FC63DAF-8483-4772-8E79-3D69D8477DE4 \
    "$RAW" >/dev/null
"$SGDISK" \
    --attributes=1:set:48 --attributes=1:set:49 --attributes=1:set:50 \
    --attributes=1:set:51 --attributes=1:set:52 --attributes=1:set:53 \
    --attributes=1:set:54 --attributes=1:set:55 --attributes=1:set:56 \
    "$RAW" >/dev/null

python3 - "$RAW" "$ATTR" <<'PY'
import struct, sys
path, want = sys.argv[1], int(sys.argv[2], 16)
with open(path, "rb") as f:
    f.seek(512)
    header = f.read(512)
if header[0:8] != b"EFI PART":
    sys.exit("primary GPT header missing")
entry_lba, entry_size = struct.unpack_from("<QI", header, 72)
with open(path, "rb") as f:
    f.seek(entry_lba * 512)
    entry = f.read(entry_size)
got = struct.unpack_from("<Q", entry, 48)[0]
print(f"kernel attributes {got:#018x}")
if got != want:
    sys.exit("kernel attributes are not priority 15, tries 15, successful 1")
PY

echo "writing kernel, boot, super, metadata, userdata"
dd if="$IMAGES/kernel.kpart" of="$RAW" bs=1048576 seek=$((P1_START / 2048)) conv=notrunc status=none
dd if="$work/pmos_boot.img" of="$RAW" bs=1048576 seek=$((P2_START / 2048)) conv=notrunc status=none
dd if="$IMAGES/super.img" of="$RAW" bs=1048576 seek=$((P3_START / 2048)) conv=notrunc status=progress
dd if="$work/metadata.img" of="$RAW" bs=1048576 seek=$((P4_START / 2048)) conv=notrunc status=none
dd if="$work/userdata.img" of="$RAW" bs=1048576 seek=$((P6_START / 2048)) conv=notrunc status=none

echo "checking super and the installer files"
super_hash="$(dd if="$RAW" bs=1048576 skip=$((P3_START / 2048)) count=8192 status=none | sha256sum | awk '{print $1}')"
want="$(awk '$1=="super.img"{print $3}' "$IMAGES/MANIFEST")"
[[ "$super_hash" == "$want" ]] || { echo "super in image is $super_hash" >&2; exit 1; }
debugfs -R 'cat kukui-install/android.kpart' "$work/pmos_boot.img" > "$work/android.kpart"
debugfs -R 'cat kukui-install/menu.kpart' "$work/pmos_boot.img" > "$work/menu.kpart"
got="$(sha256sum "$work/android.kpart" | awk '{print $1}')"
want="$(awk '$1=="android.kpart"{print $3}' "$IMAGES/MANIFEST")"
[[ "$got" == "$want" ]] || { echo "android.kpart in image is $got" >&2; exit 1; }
got="$(sha256sum "$work/menu.kpart" | awk '{print $1}')"
want="$(awk '$1=="menu.kpart"{print $3}' "$IMAGES/MANIFEST")"
[[ "$got" == "$want" ]] || { echo "menu.kpart in image is $got" >&2; exit 1; }
"$SGDISK" --verify "$RAW"
"$SGDISK" --print "$RAW"

echo "zipping $ZIP"
rm -f "$ZIP" "$SHA"
(
    cd "$OUTDIR"
    zip -6 "$(basename "$ZIP")" "$(basename "$RAW")"
    sha256sum "$(basename "$ZIP")" > "$(basename "$SHA")"
)
python3 - "$ZIP" "$NAME" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = z.namelist()
img = sys.argv[2] + ".img"
if names != [img]:
    sys.exit(f"zip should contain only {img}, has {names}")
info = z.getinfo(img)
if info.compress_type == zipfile.ZIP_STORED:
    sys.exit("image was stored uncompressed")
print(f"{img} compress_type {info.compress_type} size {info.file_size} compressed {info.compress_size}")
PY
echo "OK $ZIP"
cat "$SHA"
