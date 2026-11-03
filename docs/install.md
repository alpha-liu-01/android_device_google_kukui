# Installing

The zip is an image of a bootable USB stick. Unzip it on a computer and
write that stick. Boot the tablet from the stick with Ctrl+U. The
installer inside that Android system writes the internal eMMC.

depthcharge will not install this zip. Recovery sideload, `payload.bin`,
and fastboot are not the install path. The kernel keeps the USB
controller in host mode so the stick can be the boot disk, which means
the tablet cannot also present itself as a USB gadget for sideload.

This was tested on one Lenovo IdeaPad Duet, Google Krane sku176, with
the factory depthcharge firmware. Developer mode and USB boot are
already enabled on a machine that boots postmarketOS from USB. This
does not flash UEFI and does not replace the read-only firmware.

## What you need

- A Linux computer.
- A USB stick of about 32 to 256 GiB. The image contains an 8 GiB
  `super` partition plus an empty data partition, so a smaller stick
  does not fit.
- `sgdisk` and `make_f2fs`. A full Lineage build provides both at
  `out/host/linux-x86/bin/`. The writer does not assume they are on
  the default `PATH`.
- The stick unmounted. The script stops if any partition is mounted.

## Write the stick

The release zip contains one GPT disk image, `lineage-23.2-kukui-*.img`.
Rufus and BalenaEtcher write that zip directly. In Rufus choose DD mode
if it asks. The image is 10.9 GiB, so the stick must be at least 16 GiB.
`userdata` inside the image is 2.4 GiB and is not grown to fill a larger
stick. The installer only needs the kernel slot, `pmOS_boot`, and the
8 GiB `super`.

Linux can write the same image without unpacking it:

```
unzip -p lineage-23.2-kukui-YYYYMMDD.zip | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

`bringup/release/flash-usb.sh` is the other writer. It builds the same
partition table on the stick and gives `userdata` the rest of the disk.
Unpack is not how that script is used. It refuses to guess a disk. It
also refuses the computer's root disk, the disk that holds the home
directory, any nvme device, a disk that is not USB, and the build disk
used on the machine this tree was developed on (serial `0123456789ABC`,
model `YMTC`).

Check `lsblk` and use the whole-disk node, not a partition.

```
export SGDISK=/path/to/lineage-23.2/out/host/linux-x86/bin/sgdisk
export MAKE_F2FS=/path/to/lineage-23.2/out/host/linux-x86/bin/make_f2fs
sudo -E ./flash-usb.sh --confirm sdb /dev/sdb ./images
```

`--confirm` must be the disk's basename, here `sdb` for `/dev/sdb`.
The script prints the model, serial, and size, then wipes that disk.
Read those three lines before confirming.

The write takes several minutes. Most of that is copying and reading
back the 8 GiB `super` image. When it finishes it prints `OK` and the
disk path. It does not reboot the tablet. Unmount the stick if the
desktop mounted it after the partition table changed, then remove it.

## Boot

Plug the stick into the tablet. At the developer screen, Ctrl+U boots
from USB. The first boot of a freshly written stick has an empty data
partition, so the setup wizard runs. Wi-Fi can appear after the first
firmware probe has timed out and the system has reloaded the adapter.
That happens once per new data partition.

## Install to the internal disk

Open **Install to eMMC**. The buttons stay disabled until the running
system is the USB Android and the internal disk is the eMMC at
`11230000.mmc`.

The labels follow the system language. English and Chinese are included.

| Button | What it does |
| --- | --- |
| Android only | Replaces the internal disk with Android. An existing Linux installation on that disk is erased. |
| Android and Linux | Shrinks an existing Linux root and adds Android beside it. The screen asks for the Linux root size in GiB. Calculate, then install. |
| Update system | Replaces `super`, the Android kernel, and the boot menu with the copies on the USB stick. It does not format userdata, does not change the partition table, and does not change boot priority. |

Nothing is written until the confirm button is pressed. The confirm
text names the target device. For an update it also says that userdata
is not formatted. Leave the installer open until it tells you to unplug
the stick. It does not reboot on its own.

After it finishes, unplug the USB stick and power on. Ctrl+D opens the
boot menu when a menu was installed. The menu stays available because
its boot priority is left as it was.

An update reads the images already written on the USB stick. It does
not open a second zip from the internal data partition. To install a
newer build, write that build's zip to the USB stick, boot it, and use
**Update system**.

## What the stick contains

| Partition | Name | Contents |
| --- | --- | --- |
| 1 | `pmOS_kernel` | USB Android FIT. Boot priority 15, tries 15, successful 1. |
| 2 | `pmOS_boot` | ext4. `/kukui-install/` holds `android.kpart` and `menu.kpart`. |
| 3 | `super` | 8 GiB raw Android super image. |
| 4 | `metadata` | Empty ext4, formatted by the writer. |
| 5 | `misc` | 4 MiB, cleared. |
| 6 | `userdata` | Empty f2fs, formatted by the writer. |

The USB partition table is not the eMMC partition table. Do not copy
the stick onto the internal disk with `dd`.
