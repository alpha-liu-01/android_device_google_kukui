# Building

The Android tree is LineageOS 23.2. The kernel is not built by `lunch`.
It is Linux 6.18.28 from `linux-postmarketos-mediatek-mt81`, plus
`bringup/phase2/config.fragment` and the patches under `bringup/kernel/`
and `bringup/camera/`. The FIT images and kernel modules in this
repository are from that build. `LOCALVERSION` is `-mt81-kukui2`.

Some kernel patches depend on each other. Apply them to the 6.18.28
tree in this order:

1. The `linux-postmarketos-mediatek-mt81` patches.
2. `bringup/camera/isp/` copied to `drivers/media/platform/mediatek/isp`,
   then `bringup/camera/kernel-camera.patch`.
3. `bringup/kernel/pm-set-mem-sleep.patch`. It adds the
   `pm_set_mem_sleep()` helper that the next patch calls.
4. `bringup/kernel/mt8183-usb-suspend-power.patch`
5. `bringup/kernel/mtk-vcodec-enc-data-offset.patch`
6. `bringup/kernel/drm-setmaster-takeover.patch`. Without it,
   drm_hwcomposer cannot become DRM master and the panel stays dark.
7. `bringup/kernel/cgroup-v1-cap-sys-nice.patch`
8. `bringup/kernel/auxadc-thermal-sensor-zones.patch`
9. `bringup/kernel/mtk-cci-devfreq-opp-disable.patch`
10. `bringup/kernel/panfrost-devfreq-opp-notifier.patch`
11. `bringup/kernel/mtk-mdp3-mt8183-scp-abi.patch`. It matches
    `mtk-mdp3` to the ChromeOS SCP firmware. Rebuild `mtk-mdp3.ko`
    and ship that module. This patch is not in the FIT kernel image.
12. `bringup/kernel/camera-sensor-system-sleep-pm.patch` and
    `bringup/kernel/dw9768-power-while-streaming.patch`. Rebuild
    `ov8856.ko`, `ov02a10.ko`, and `dw9768.ko`.
13. `bringup/kernel/sbs-battery-time-to-empty-enodata.patch`. Rebuild
    `sbs-battery.ko`.
14. `bringup/kernel/wakeup-reasons-sysfs.patch`. It is in the USB and
    eMMC kernel image. `bringup/kernel/mtk-drm-mt8183-min-fb-size.patch`
    is not applied: a 42 px status bar on an OVL plane flashes the
    setup wizard when the page changes. The 64x64 default stays.
15. `bringup/kernel/mt8183-kukui-firmware-cells.patch`. Rebuild the
    board DTBs. Depthcharge fills the `/firmware` node.

`CONFIG_LRU_GEN` changes core structures, so every module in the USB
ramdisk and in `vendor_dlkm` comes from that same build. `CONFIG_RTC_HCTOSYS`
stays off: the MT6358 RTC reads 2086. The menu FIT stays on the
2026-10-31 kernel.

Patches 8 to 10 are what mtk-svs needs to finish its init on MT8183. It
also needs `CONFIG_ARM_MEDIATEK_CCI_DEVFREQ=y` from
`bringup/phase2/config.fragment`. The configuration is the postmarketOS
mt81 config merged with `bringup/phase2/config.fragment`,
`bringup/camera/config.fragment`, and `bringup/kernel/resukisu.fragment`.
The menu FIT stays on the 2026-10-31 kernel. Patches 7 to 10 and 14 to
15 go into the USB and eMMC FITs only.

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

The DTB inside the FITs is selected by depthcharge. Krane is the
default: running `pack-install-fits.sh` without extra variables keeps
the Krane sku176 and sku0 configurations and adds Kodama sku16.
`build-images.sh` requires all three names when the FIT contains a
Krane name. Passing `KUKUI_DTB` for one other board still replaces
that set with the single board DTB.

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
