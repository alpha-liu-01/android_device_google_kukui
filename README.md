# LineageOS 23.2 for Google Kukui (Krane and Kodama)

LineageOS 23.2, Android 16, for MT8183 Kukui boards. Tested on the
Lenovo IdeaPad Duet (Google Krane, sku176) and Google Kodama (sku16).
The bootloader stays the factory ChromeOS depthcharge. The image
boots from a USB stick with Ctrl+U, and an installer in that system can
copy it onto the internal eMMC.

The machine this tree was brought up on already had postmarketOS on the
eMMC. The installer can leave that Linux install in place and add Android
beside it, or it can replace the internal system and keep the existing
Android data partition.

## Status

Tested on one Krane sku176 and one Kodama sku16. Other Kukui boards are
not tested.

The current image reaches the desktop from USB and from the internal
disk. On Krane, the keyboard, touchscreen, stylus, Wi-Fi, Bluetooth HID,
cameras, battery, and sensors work. On Kodama, display, touch, stylus,
Wi-Fi, audio, keyboard, battery, and sensors work, but the camera does
not: `dumpsys media.camera` reports 0 devices because the
camera HAL and devicetree in this tree are Krane/OV8856-specific and
Kodama uses an OV5695 sensor. Video playback uses the hardware H.264
decoder. SELinux is permissive. An external display is not implemented.

See [docs/kodama.md](docs/kodama.md) for the Kodama test matrix and
limitations, and [docs/adapting-boards.md](docs/adapting-boards.md) for
adding another Kukui board.

The engineering notes under `docs/` are in Chinese. The build and
install instructions below are the ones to follow.

## Install

The download is a USB image, not a recovery package. depthcharge does
not run `adb sideload` or an `updater-script`.

See [docs/install.md](docs/install.md).

## Build

See [docs/build.md](docs/build.md).

```
patches/apply-patches.sh /path/to/lineage-23.2
```

Lunch target: `lineage_kukui-trunk_staging-userdebug`.

## Layout

| Path | What it is |
| --- | --- |
| `device/google/kukui` | The device tree. Soong does not follow a directory symlink, so a Lineage tree needs one symlink per file. `patches/apply-patches.sh` creates those links. |
| `local_manifests/kukui.xml` | LineageOS 23.2 projects this build needs beyond the default manifest. |
| `patches/` | Changes to the Lineage tree. They are not Gru patches. |
| `bringup/release/` | Builds the USB zip and writes a USB stick. |
| `bringup/boards/` | Board DTB build helper (`build-dtb.sh`). |
| `bringup/kernel/`, `bringup/camera/` | Kernel and camera patches on top of Linux 6.18.28-mt81. |

## License

The device tree is Apache 2.0. See [LICENSE](LICENSE).

Kernel modules and kernel patches are GPL-2.0-only. The Wi-Fi, Bluetooth,
and SCP firmware files, and the camera prebuilts, keep the licenses named
in [NOTICE](NOTICE). Those licenses are also stored next to the firmware.
