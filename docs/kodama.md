# Google Kodama (sku16)

Kodama is an MT8183 Kukui board. This tree was tested on one
`google,kodama-sku16` device. Other Kodama SKUs are not tested.

## Status

| Area | Result |
| --- | --- |
| Display | Works. Mainline 6.18.28 Kodama DTB, panel `auo,b101uan08.3`. |
| Touch / stylus | Works with the `04F3:2ABE` IDC files in this tree. |
| Wi-Fi | Works. ath10k SDIO QCA6174. |
| Bluetooth | Not tested. |
| Audio / microphone | Works with the existing Kukui audio HAL and UCM. |
| Keyboard / touchpad | Works. Hammer keyboard cover over the internal USB hub. |
| Battery / charger | Works. Battery and charger are reported. |
| Sensors | Accelerometer and gyroscope are present. |
| Brightness | Works. |
| eMMC install | Works with the Android-only installer path. |
| Camera | **Not working. `dumpsys media.camera` reports 0 camera devices.** |
| External display | Not implemented. |
| SELinux | Permissive. |

### Camera is not supported

The camera stack in this tree is Krane-specific: the prebuilt
`libcamera` HAL, `camera_hal.yaml`, and tuning files describe the Krane
rear sensor (OV8856) and front sensor (OV02A10). Kodama sku16 uses an
OV5695 rear sensor, and the mainline 6.18 Kodama DTS does not contain
camera, CSI PHY, `seninf`, or CAMSV nodes. As a result the camera
service starts with zero devices.

Camera support is a separate bring-up. Do not include camera changes in
a board-support patch unless they have been tested on the board.

## Device tree

Build the Kodama DTB from a Linux 6.18.28 source tree:

```
LINUX_SRC=/path/to/linux-6.18.28 \
KUKUI_COMPAT=google,kodama-sku16 \
  bringup/boards/build-dtb.sh /tmp/kodama-dtb
```

The script compiles:

```
arch/arm64/boot/dts/mediatek/mt8183-kukui-kodama-sku16.dts
```

and checks that the result contains `google,kodama-sku16` and
`mediatek,mt8183`. The expected panel compatible is
`auo,b101uan08.3`.

Do not commit the generated DTB. Keep it under `work/` or another
gitignored build directory.

## Touch

Kodama sku16 enumerates the Elan touch controller as:

```
hid-over-i2c 04F3:2ABE
hid-over-i2c 04F3:2ABE Stylus
```

The two IDC files in `device/google/kukui/idc/` set
`touch.deviceType = touchScreen` and
`touch.orientation = ORIENTATION_270`. They are copied to
`/vendor/usr/idc/` by `device.mk`.

If another Kodama SKU uses a different controller, add a new IDC named
after the input device rather than changing these files.

## Pack the FITs

A Krane release FIT already includes `mt8183-kukui-kodama-sku16` as
`conf-3`, next to Krane sku176 and sku0. depthcharge picks it when the
board compatible is `google,kodama-sku16`. The commands below build a
Kodama-only FIT instead, replacing the Krane configurations.

Pass the Kodama DTB and a FIT that contains the shared kernel and
ramdisk:

```
KUKUI_BOARD=kodama \
KUKUI_DTB=/tmp/kodama-dtb/mt8183-kukui-kodama-sku16.dtb \
KUKUI_KERNEL_FIT=/path/to/kernel.kpart \
  bringup/phase4/pack-install-fits.sh \
    /tmp/kodama-payload \
    /path/to/kukui-keep-emmc \
    /path/to/kukui-menu
```

The script

- checks the DTB compatible string;
- uses the DTB in the Android FIT and the boot-menu FIT;
- writes `android.kpart`, `menu.kpart`, and `android/kodama.dtb`;
- keeps the USB and eMMC command lines unchanged;
- skips the legacy Linux/kexec payload for non-Krane boards.

`bringup/release/build-images.sh` then copies the kparts and the 8 GiB
`super.img` into the release directory.

## eMMC install

Kodama sku16 has a 29.1 GiB eMMC. The Android-only layout used here is:

| Partition | Size |
| --- | --- |
| kernel slot | 32 MiB |
| `super` | 8 GiB |
| `metadata` | 16 MiB |
| `misc` | 4 MiB |
| `userdata` | remainder, about 20.7 GiB |

Use **Android only** in the installer. The Android-and-Linux path is
for postmarketOS layouts and does not apply to a Debian install.

The installer writes the Kodama `android.kpart` to the eMMC kernel slot.
A Krane `android.kpart` will not work correctly on Kodama.

## Time

Kodama has no RTC. Android starts at the build time until network time
is available. Keep automatic time and time zone enabled and use an NTP
server reachable from the local network. Do not hard-code a server,
credentials, or an IP address in the tree.

## Tested matrix

| Test | Result |
| --- | --- |
| USB boot with Ctrl+U | Pass |
| eMMC boot with `boot_devices=soc/11230000.mmc` | Pass |
| Touch direction | Pass, `ORIENTATION_270` |
| Wi-Fi association | Pass |
| Audio playback / microphone | Pass |
| Battery level and charging status | Pass |
| Sensors | Pass |
| Camera | Fail, 0 devices |
| SELinux enforcing | Not tested |

## Known limitations

- Camera not supported (see above).
- External display not implemented.
- SELinux is permissive.
- Charger behavior above 5 V was not tested.
- Only `kodama-sku16` was tested. Other Kodama SKUs may use different
  panels or touch controllers.
- Wired USB adb/MTP is not implemented; the USB controller stays in
  host mode for USB boot. Use wireless adb.
