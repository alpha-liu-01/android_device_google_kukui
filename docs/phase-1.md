# 阶段 1：启动契约

2026-10-30 结束。路线图在 [roadmap.md](roadmap.md)，基线在 [阶段 0](phase-0.md)。

第二次 Ctrl+U 用带 `usb-storage` 的 FIT 启动，把 `kukui-android phase1` 和完整 `dmesg` 写进了 U 盘的 `pmOS_boot`。没有挂 postmarketOS 的根，没有写 eMMC。不按 Ctrl+U 的下一次启动回到 eMMC 上的 postmarketOS v26.06，Plasma 的 Wayland 会话在跑。日志副本是 [bringup/phase1/kukui-phase1.log](../bringup/phase1/kukui-phase1.log)，703 行，sha256 `a19c3cf30a371524e7c92673cbb855b0926a324fd20776004201339a3086802f`。

## 和路线图初稿的差别

路线图初稿要在 U 盘上新建一个卷标 `bootlog` 的 ext4。这张盘做不到，也不该做。

U 盘是 `/dev/sdb`，`TRAN` 走 USB（`/sys/devices/.../usb2/2-8/...`），型号 `SD/MMC`，122,167,296 扇区。分区和 eMMC 上正在跑的那份是同一份 GPT，因为这台机器没有 ChromeOS，eMMC 上的 postmarketOS 是先从 U 盘启动、再把同一份镜像 `dd` 进去的。所以两边的 `PARTUUID` 和文件系统 UUID 都一样，`kern_guid=%U` 分不出哪一块盘。

| 分区 | 起始扇区 | 扇区数 | `PARTNAME` | 文件系统 |
| --- | --- | --- | --- | --- |
| sdb1 | 8192 | 65536（32 MiB） | `pmOS_kernel` | 无。这是这次唯一的写入目标 |
| sdb2 | 73728 | 1048576（512 MiB） | `pmOS_boot` | ext2，卷标 `pmOS_boot`，UUID `38f0e7d6-fa7d-471b-b14f-5236254f0be1` |
| sdb3 | 1122304 | 121044959 | `pmOS_root` | ext4，卷标 `pmOS_root` |

`sdb3` 之后只剩 33 个扇区。不缩小 `pmOS_root`，不新建分区。日志写到 U 盘已有的 `pmOS_boot`，文件名 `/kukui-phase1.log`。

init 只在 `/sys/block/sd*` 下面找 `PARTNAME=pmOS_boot`。`mmcblk*` 一律不挂、不写。按 UUID 或卷标挂会挂到 eMMC 上那份同名分区。

板名用 `krane`，不是 deviceinfo 里的 `mt8183`。这台平板上的 `depthchargectl` 把代号 `krane` 认成 Lenovo IdeaPad Chromebook Duet，`dt-compatible` 是 `google,krane`。`boards.ini` 里没有代号 `mt8183`，芯片集那节的代号是 `chipset-mt8183`。镜像里只有一块 DTB：`mt8183-kukui-krane-sku176.dtb`。多块 DTB 时才需要 pmOS 那种 `mt8183` 板名。

没有在平板上跑 `depthchargectl write`。那个命令写的是平板自己的磁盘，也就是 eMMC。工作站上对 `/dev/sdb1` 做 `dd` 只覆盖分区内容，不改 GPT 的启动优先级，效果和 `--no-prioritize` 一样。原来的优先级还在，Ctrl+U 仍选这块分区。

## 用的文件

U 盘根上的内核和阶段 0 在 eMMC `/boot` 里记下的是同一份字节。

| 文件 | 字节 | sha256 |
| --- | --- | --- |
| `vmlinuz` | 13,487,996 | `be8714aafa8302548c176f3627bdbf5976a856aed0f33ceaf420b736c4b5af53` |
| `mt8183-kukui-krane-sku176.dtb` | 61,542 | `852744daac3c6290009cb3dd5cb7f321aea10e29ab0526aa13b76f757f5503d5` |
| 原来的 `vmlinuz.kpart` | 24,723,456 | `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e` |

原来的 FIT 已复制到 `work/phase1/pmos-vmlinuz.kpart`（不进 git）。Ctrl+U 进不了这个标记 init 时，把这份写回 `sdb1` 就能恢复 U 盘上的 postmarketOS 内核。eMMC 上的 `vmlinuz.kpart` 没有动。

第一份 initramfs 是 newc cpio，1,646,080 字节，sha256 `85859a28756aeda28d36449e802bb2e4ef7352d555e2ef19a3998bb769da1878`。里面是 `/init`、U 盘根上的 aarch64 `busybox`，以及 `/lib/ld-musl-aarch64.so.1` 和指向它的 `libc.musl-aarch64.so.1`。`busybox` 是动态链接的，缺这个解释器的话内核执行不了 `/init`。

第二次的 initramfs 在此基础上加了未压缩的 `usb-storage.ko`（1,811,968 字节，sha256 `d1c620a69721c38a4d97caa114d99c3d20aad4105f0bfe3d413bf57bff8501ad`）。模块来自这份内核的 `/lib/modules/6.18.28-mt81`，vermagic 是 `6.18.28-mt81 SMP preempt mod_unload aarch64`，`modules.dep` 里没有别的依赖。磁盘上的是 `.zst`，init 里放的是解压后的 ELF，因为这个 init 的 `insmod` 不解压。

## init 做什么

脚本在 `bringup/phase1/init`。

1. `busybox --install`，挂上 devtmpfs、proc、sysfs。先建这几个目录。
2. 往 `/dev/kmsg` 写一行 `kukui-android phase1`。
3. `insmod /lib/modules/usb-storage.ko`。这颗内核的 `CONFIG_USB_STORAGE=m`，读卡器没有这个模块就不会变成 `sd*`。
4. 最多等 30 秒，在 `sd*` 的分区里找 `PARTNAME=pmOS_boot`，只挂这一块，挂到 `/bootlog`。
5. 立刻把 `kukui-android phase1`、`uname`、命令行和块设备 uevent 写到 `/kukui-phase1.log`。
6. 再等 8 秒，把 `dmesg` 追加进去，最后一行是 `=== end ===`，然后 `sync`。
7. 之后一直睡眠。不挂 `pmOS_root`，不写任何 `mmcblk`。找不到分区时，把 `/sys/block` 的名字打到 `kmsg`，方便从屏幕上看。

## 构建

在 `user@10.0.0.117` 上执行。工作站没有 `depthchargectl` 和 `futility`。签名用的是平板上 `/usr/share/vboot/devkeys/` 的开发者密钥。

```text
depthchargectl build --board krane \
  --kernel /boot/vmlinuz \
  --dtbs /boot/mt8183-kukui-krane-sku176.dtb \
  --initramfs /home/user/phase1/initramfs.cpio \
  --compress lzma --root none \
  --kernel-cmdline "console=tty0 loglevel=7 deferred_probe_timeout=30" \
  -o /home/user/phase1/kernel.kpart
```

工具自己加上 `kern_guid=%U`。核对过的命令行是：

```text
kern_guid=%U console=tty0 loglevel=7 deferred_probe_timeout=30
```

没有 `root=`，没有 `pmos_root_uuid`。内核 lzma 后 9,623,730 字节，FIT 里的 DTB 名是 `mt8183-kukui-krane-sku176`。`depthchargectl check` 退出码 0，并说明它现有的检查不完整。

第一份镜像 11,411,456 字节，sha256 `8868f7ffdb3fb08ebf6f2ba3b256109457e7d65a35ab1d760a7dd6988c5dca20`。它能启动，但 init 找不到 U 盘，见下面的第一次 Ctrl+U。

正在使用的是第二份，initramfs 里带了 `usb-storage.ko`。11,579,392 字节，小于 32 MiB 分区。sha256：

```text
3ef3953f79e6f36a03b093602d615a2aa1107f158beaa48875d6965ba8237f72
```

副本在 `work/phase1/kernel.kpart`。平板上还有一份 `/home/user/phase1/kernel.kpart`。

## 写入

工作站的根在 `/dev/nvme0n1p4`，不是 `sdb`。`sdb1` 的 `PARTNAME` 是 `pmOS_kernel`，起始扇区 8192，长度 65536。`sudo -n` 要密码，实际用 `pkexec` 跑了 `bringup/phase1/write-usb-kernel.sh`。脚本再次核对 USB、分区名、几何、根磁盘和镜像校验和，`dd` 到 `/dev/sdb1`，再读回比对。

第一次写入读回 11,411,456 字节，sha256 `8868f7ffdb3fb08ebf6f2ba3b256109457e7d65a35ab1d760a7dd6988c5dca20`。第二次写入读回 11,579,392 字节，sha256 `3ef3953f79e6f36a03b093602d615a2aa1107f158beaa48875d6965ba8237f72`。U 盘 `pmOS_boot` 里原来的 `vmlinuz.kpart` 两次都没变。

eMMC 没有写。第二次写入之后平板仍是 Ctrl+U 之后那一次启动，`boot_id` 是 `04c5ce25-b83c-4f71-8ee2-be630de8f4c2`，根仍是 `/dev/mmcblk0p3`，`/boot/vmlinuz.kpart` 的 sha256 仍是 `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e`。阶段 0 没能读到 `/dev/mmcblk0p1` 的原始校验和，平板上仍没有免密 root，所以那一项还空着。

## 第一次 Ctrl+U

Ctrl+U 进了这份 FIT。屏幕上先有 `Run /init as init process` 和 `kukui-android phase1`，然后 USB 枚举了内部 hub `05e3:0610`、Hammer 键盘 `18d1:503c`，以及读卡器 `0bda:0316`（`USB3.0-CRW`）。最后停在 `kukui-android phase1 no boot partition`。没有 SCSI 磁盘行。

`pmOS_boot` 上没有 `kukui-phase1.log`，分区里的文件时间仍是 10 月 23 日。读卡器的接口类是 `08/06/50`（Bulk-Only SCSI）。工作站上绑的驱动是 `usb-storage`，不是 `ums-realtek`。这颗内核里 `CONFIG_USB_STORAGE=m`，`CONFIG_USB_STORAGE_REALTEK` 没打开，`CONFIG_BLK_DEV_SD=y`。第一份 initramfs 没有模块，所以读卡器停在 USB 设备，变不成 `sd*`。

不按 Ctrl+U 的那次重启回到了 eMMC。SSH 仍在，根是 `mmcblk0p3`，内核仍是 `6.18.28-mt81`，`vmlinuz.kpart` 校验和没变。

## 第二次 Ctrl+U

日志第一行是 `kukui-android phase1`，最后一行是 `=== end ===`。中间有 `uname`、命令行、块设备 uevent 和 `dmesg`。

命令行与构建时一致：

```text
cros_secure kern_guid=61e1577f-bd28-2941-90fc-972eb9557a1b console=tty0 loglevel=7 deferred_probe_timeout=30
```

没有 `root=`。`kern_guid` 是内核分区的 `PARTUUID`。U 盘的 `sda1` 和 eMMC 的 `mmcblk0p1` 都是 `61e1577f-bd28-2941-90fc-972eb9557a1b`，另外两对分区的 `PARTUUID` 也同样重复。init 没有按这个 UUID 选盘，挂的是 `/dev/sda2`（`PARTNAME=pmOS_boot`）。`dmesg` 里只有这一次挂载：ext2 `38f0e7d6-fa7d-471b-b14f-5236254f0be1`，读写。没有挂 `sda3`，也没有挂 `mmcblk0p3`。

`insmod usb-storage` 之后，读卡器 `0bda:0316` 变成 `scsi host0`，`sda` 有 122,167,296 个扇区，分区 `sda1 sda2 sda3`。它接在 `11200000.usb` 的 xHCI 上，路径经过内部 hub 的 `1-1.2`。阶段 3 的 `androidboot.boot_devices` 用 `11200000.usb`。eMMC 仍是 `11230000.mmc` 上的 `mmcblk0`（DV6DAB，116 GiB，`p1 p2 p3`）。

同一份日志里还能看见：机型 `MediaTek krane sku176 board`，`mediatek-drm` 绑上 DSI 并建立 `fb0`（fbcon 240×75），只建了一个 CRTC。Panfrost 初始化了 Mali-G72，并有一行 `Failed to register cooling device`。`zram0` 节点存在，没有被挂上。没有 panic。

不按 Ctrl+U 的下一次启动：`boot_id` 是 `580f3546-f460-45a8-8651-b1001047554a`，根是 `/dev/mmcblk0p3`，发行版 postmarketOS v26.06，内核 `6.18.28-mt81`。seat0 上有 `startplasma-wayland`、`kwin_wayland` 和 `plasmashell`。`/boot/vmlinuz.kpart` 的 sha256 仍是 `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e`。`/dev/mmcblk0p1` 的原始校验和这次还是没读到，平板上没有免密 root；这次启动没有写那一块分区。
