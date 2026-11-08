# Adapting another Kukui board

This is the generic procedure used for Kodama sku16. It applies to
MT8183 Kukui boards that boot a mainline Linux kernel. Keep the patch
board-local: do not mix in another board's camera, audio, or touch
changes.

## 0. Collect the device facts

From a running Linux system on the board:

```
cat /proc/device-tree/compatible
cat /proc/device-tree/model
```

Record the exact `compatible` string, for example
`google,kodama-sku16`. Identify the panel compatible, the touch
controller, the eMMC size, and whether the board has an RTC.

Do not put serial numbers, Wi-Fi credentials, IP addresses, or SSH keys
in the tree or in the commit message.

## 1. Build the board DTB

Use the mainline source tree that matches the kernel build. For this
tree that is Linux 6.18.28.

```
LINUX_SRC=/path/to/linux-6.18.28 \
DTS=/path/to/linux-6.18.28/arch/arm64/boot/dts/mediatek/mt8183-kukui-<board>-sku<N>.dts \
KUKUI_COMPAT=google,<board>-sku<N> \
  bringup/boards/build-dtb.sh /tmp/<board>-dtb
```

The script preprocesses the DTS, compiles it with `dtc`, and verifies
the root compatible and `mediatek,mt8183`.

Check the panel node in the resulting DTB. A DTB from a different board
can boot the kernel but will program the wrong panel and leave the
screen black or full of artifacts.

## 2. Add a touch IDC

List the input devices:

```
adb shell getevent -pl
```

For a HID-over-I2C touch controller the name looks like:

```
hid-over-i2c 04F3:2ABE
```

The IDC file name replaces spaces and colons with underscores:

```
hid-over-i2c_04F3_2ABE.idc
```

Start from the existing Krane files and adjust only `touch.orientation`
when the panel scanout differs. Install the file from `device.mk`:

```make
$(LOCAL_PATH)/idc/<name>.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/<name>.idc \
```

Keep a separate file for the stylus node if the kernel names it
differently.

## 3. Pack the FITs

Use the shared kernel/ramdisk FIT and the new DTB:

```
KUKUI_BOARD=<board> \
KUKUI_DTB=/tmp/<board>-dtb/<dtb-name>.dtb \
KUKUI_KERNEL_FIT=/path/to/kernel.kpart \
  bringup/phase4/pack-install-fits.sh \
    /tmp/<board>-payload \
    /path/to/kukui-keep-emmc \
    /path/to/kukui-menu
```

`pack-install-fits.sh` defaults to Krane and, for that board, also adds
the sku0 panel configuration. For a new board it:

- replaces the FIT DTB;
- verifies the compatible string;
- keeps the USB command line
  `androidboot.boot_devices=soc/11201000.usb/11200000.usb`;
- keeps the eMMC command line
  `androidboot.boot_devices=soc/11230000.mmc`;
- writes `android.kpart`, `menu.kpart`, and the board DTB;
- skips the legacy Linux/kexec payload (Android-only bring-up).

Then build the release directory:

```
bringup/release/build-images.sh /tmp/<board>-images /tmp/super.raw
bringup/release/pack-zip.sh /tmp/<board>-images /tmp/<board>-usb.zip
```

## 4. Install to eMMC

The installer writes the `android.kpart` from the USB stick to the eMMC
kernel slot. A Krane `android.kpart` will not work correctly on another
board.

Use **Android only** for a board that does not have a postmarketOS
partition layout. The Android-and-Linux path expects a postmarketOS
layout and must not be used for a Debian install.

Record the resulting sizes: kernel slot, 8 GiB `super`, `metadata`,
`misc`, and the remaining `userdata`.

## 5. Validate before writing eMMC

Boot from USB and check, in this order:

1. Display is correct at the native panel resolution.
2. Touch direction matches the display; `dumpsys input` shows the
   expected orientation.
3. Wi-Fi associates.
4. Audio playback and microphone work.
5. Battery and charger are reported.
6. Sensors and brightness work.
7. Camera status is recorded. `dumpsys media.camera` may report zero
   devices; do not claim camera support unless preview and capture were
   tested.

Only then install to eMMC.

## 6. Document the result

Add a `docs/<board>.md` with:

- exact `compatible` string and tested SKU;
- panel and touch controller;
- the DTB source and build command;
- what works and what does not;
- camera status, even when it is "not supported";
- eMMC layout;
- known limitations.

Update `README.md` Status and `docs/build.md` only with tested facts.

## 7. What not to commit

- generated DTBs, kernel images, `super.img`, or kparts;
- `work/` output;
- serial numbers, hardware IDs that identify a person, IP addresses,
  Wi-Fi credentials, SSH keys, or passwords;
- camera changes that were not tested on the board;
- changes for other boards in the same patch.

Keep the patch limited to the DTB selection, the touch IDC, and the
documentation for the new board.
