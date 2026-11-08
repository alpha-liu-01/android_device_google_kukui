# Building

The Android tree is LineageOS 23.2. The kernel is not built by `lunch`.
It is Linux 6.18.28 from `linux-postmarketos-mediatek-mt81`, plus
`bringup/phase2/config.fragment` and the patches under `bringup/kernel/`
and `bringup/camera/`. The FIT images and kernel modules in this
repository are from that build. `LOCALVERSION` is `-mt81-kukui2`.

A USB image needs four pieces:

| File | Role |
| --- | --- |
| `kernel.kpart` | FIT the USB stick itself boots. Command line uses `androidboot.boot_devices=soc/11201000.usb/11200000.usb`. |
| `android.kpart` | FIT written to the eMMC Android kernel slot. Command line uses `androidboot.boot_devices=soc/11230000.mmc`. |
| `menu.kpart` | Boot menu FIT. Command line contains `console=ttynull`. |
| `super.img` | Raw dynamic-partition image, exactly 8589934592 bytes. |

`super.img` comes from the Lineage build. The three FIT files come from
the kernel build. `bringup/release/build-images.sh` only checks and
copies them. It does not compile either tree.

## Board DTB

The DTB inside the FITs is board-specific. Krane is the default:
running `pack-install-fits.sh` without extra variables keeps the Krane
FIT, including both the sku176 and sku0 configurations. `build-images.sh`
requires those two names only when the FIT is a Krane FIT.

For another Kukui board, build its DTB from the same Linux 6.18.28 tree:

```
LINUX_SRC=/path/to/linux-6.18.28 \
KUKUI_COMPAT=google,kodama-sku16 \
  bringup/boards/build-dtb.sh /tmp/kodama-dtb
```

Then repack the FITs with the board DTB and a FIT that contains the
shared kernel and ramdisk:

```
KUKUI_BOARD=kodama \
KUKUI_DTB=/tmp/kodama-dtb/mt8183-kukui-kodama-sku16.dtb \
KUKUI_KERNEL_FIT=/path/to/kernel.kpart \
  bringup/phase4/pack-install-fits.sh \
    /tmp/kodama-payload \
    /path/to/kukui-keep-emmc \
    /path/to/kukui-menu
```

`pack-install-fits.sh` validates the DTB compatible string, keeps the
USB and eMMC command lines unchanged, and uses the same DTB for
`android.kpart` and `menu.kpart`. Non-Krane boards skip the legacy
Linux/kexec payload.

See [docs/kodama.md](kodama.md) for the tested Kodama configuration and
[docs/adapting-boards.md](adapting-boards.md) for another board.

## Lineage tree

The extra projects are in `local_manifests/kukui.xml`. They are upstream
LineageOS 23.2 repositories. The manifest does not fetch `device/google/gru`.

```
mkdir -p .repo/local_manifests
cp /path/to/android_device_google_kukui/local_manifests/kukui.xml .repo/local_manifests/
repo sync
```

`patches/apply-patches.sh` links this device tree into
`device/google/kukui` and applies the patches. Run it on a clean 23.2
tree. Do not pass `--reverse` before a Kukui build. `--reverse` removes
the Kukui audio, healthd, and decoder changes so the same tree can build
Gru again.

```
/path/to/android_device_google_kukui/patches/apply-patches.sh /path/to/lineage-23.2
cd /path/to/lineage-23.2
source build/envsetup.sh
lunch lineage_kukui-trunk_staging-userdebug
m superimage
```

`m superimage` writes `out/target/product/kukui/super.img`. The build
often leaves that file sparse. Expand it before packaging:

```
simg2img out/target/product/kukui/super.img /tmp/super.raw
```

The raw file must be exactly 8589934592 bytes. `build-images.sh` accepts
a sparse image and expands it when the first four bytes are the sparse
magic.

The build also needs `kukui-keep`, `kukui-keep-emmc`, and `kukui-menu`
when the FIT ramdisks are repacked. Those targets are part of the same
lunch:

```
m kukui-keep kukui-keep-emmc kukui-menu
```

Host `clang` is for the kernel only. The Android build uses the Clang
in the Lineage prebuilts.

## USB zip

`bringup/release/build-images.sh` reads four inputs and writes
`kernel.kpart`, `android.kpart`, `menu.kpart`, `super.img`, and
`MANIFEST`. The defaults are the files under `work/phase4/` in a local
bring-up tree. Pass the super image as the second argument when it lives
somewhere else. The script checks the FIT command lines and refuses a
super image that is not 8 GiB after expansion.

```
bringup/release/build-images.sh /tmp/kukui-images /tmp/super.raw
bringup/release/pack-zip.sh /tmp/kukui-images /tmp/kukui-usb.zip
```

`pack-zip.sh` stores the images uncompressed and keeps `flash-usb.sh`
executable. The zip also contains `LICENSE`, `NOTICE`, and the firmware
license texts. There is no `payload.bin` and no recovery `updater-script`.

`work/` is gitignored. Build products stay out of this repository.

The older writers under `bringup/phase1/`, `bringup/phase3/`, and
`bringup/phase4/write-sandisk.sh` record how one particular stick was
written during bring-up. A release uses `bringup/release/flash-usb.sh`
only.
