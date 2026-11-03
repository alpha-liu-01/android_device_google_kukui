# 安装到 eMMC

2026-11-02。路线图在 [roadmap.md](roadmap.md)。不写 eMMC，不刷 UEFI，不换内核。U 盘上的 Android 仍然用现在的命令行，`androidboot.boot_devices` 还是 `soc/11201000.usb/11200000.usb`。内置盘上的 postmarketOS 留着。

`94143d20b52695a48997c1cf59d2302ad07552130c9eb464dbb916420029fbe8` 那张 super 上，IPA 工作程序是 `0644`，安装器算术会溢出。`9bcc6eeed6d03b6acd12a452cb0f2129d04cdd2c5be2afdc73399ec0fef90ced` 修了这两处，并且能填 Linux 根分区的 GiB。这张已经被 Ctrl+U 过：相机可以打开。点了双系统安装之后，进度画在桌面标题栏下面，全屏时窗口看起来是空的。强退应用不会停掉后台安装。eMMC 上的 Linux 根已经被缩到 40 GiB，`menu_kernel`、`android_kernel`、`bootmenu`、`super`、`metadata`、`misc`、`userdata` 都已建好，`bootmenu` 已格式化。super、metadata、userdata 没写完，启动优先级也没改。现在 Ctrl+D 仍进原来的 postmarketOS，命令行还是原来的 `pmos_root_uuid`。

再一次 Ctrl+U 大约 5 秒就回到开发者屏幕。内核已经起来，`kukui-phase3.log` 停在 4.4 秒：`/dev/block/by-name/super` 不存在，first-stage init 重启。eMMC 上新建的分区也叫 `super`。init 先扫到它，就不再等 U 盘上的那个，符号链接没有建成。内核 lzma（crc32 `f3ea1c10`）和 `mt8183-kukui-krane-sku176.dtb`（crc32 `756e2f96`）没换，命令行仍是 `androidboot.boot_devices=soc/11201000.usb/11200000.usb`。ramdisk 里的 init 换成只认启动盘分区的版本，BuildID `b7b4d9aa303cba7c8e2b9ac1bd675ee2`。新内核槽 sha256 `5dced3f0cc7ccebd34ad2b9ead8c99f60a1b1946dfc30e58e3788c1cd95e6c33`，读回一致，优先级仍是 15、tries 15、successful 1。这次 Ctrl+U 还没有做。

eMMC 用的 `android.kpart` 也换成了同一版 init，命令行仍是 `boot_devices=11230000.mmc`，sha256 `d46ae6216dc658661a02aad0de6e3d46680d589872216ddd9e82d75907a12e6d`。它在 U 盘 `/kukui-install/android.kpart`。安装器下次写入 eMMC 时用的是这一份。

U 盘上现在这份 super 的 sha256 是 `76887347656c4b00509064299bf05c5f19e44572eafef68ecd672400febedb73`，2026-11-02 写入 SanDisk（序列号 `000000002959`）第 3 分区，整段读回一致。安装进度改到窗口中间，并留出标题栏的空档。长步骤会写明“百分比会停在这里”。已经缩到目标大小的根分区不会再缩一次。分区表如果已经是这次算出的布局，就不再调用 `sgdisk`。这台机器上的 `sgdisk` 不接受 `-a`，带上它会把对齐数字当成磁盘名，报“建立双系统分区失败”。2026-11-02 这次 Ctrl+U 已经进了 Android。正在运行的安装器是绑在 `/vendor/bin/kukui-installd` 上的修正脚本，重启会回到镜像里的旧脚本。镜像里的 super 还是 `76887347656c4b00509064299bf05c5f19e44572eafef68ecd672400febedb73`。

40 GiB 那次双系统写入已经走完，菜单能出来。画面左半边仍是内核日志，盖住 Android；键盘打出来的字落在这块控制台上。选单的 initramfs 没有装 `evdev`，`/dev/input/event*` 不存在，所以触摸、音量键都到不了选单，键盘字母才会出现在控制台上。音量键不需要新的 GPIO：EC 的 `cros-ec-keyb-switches` 已经编进内核。新的 `menu.kpart` 是 10383360 字节，sha256 `542239c3a13021efc6627cd95474c44273ca248ef0a958cd24fd0bec31e9919f`，命令行是 `console=ttynull`。没有底座键盘时，点按钮直接进入；音量加再按一次进 Android，音量减再按一次进 Linux，电源键确认当前项。内核 lzma 和 sku176 DTB 没换。上一份菜单能选中，但 `kexec_file_load` 的 initrd 文件描述符是 -1，内核直接拒绝，所以只闪一下并留在原选项。补上真实 initrd 之后，点 Android 或 Linux 都不再显示 FAILED：屏幕黑掉，背光也关掉，停很久。`/sys/fs/pstore` 是空的。这次跳转对两个系统一样，所以不是 Android 能不能从 eMMC 启动的问题。菜单不再走 kexec。选中一项之后只改分区属性：选中的槽是 priority 15、tries 1、successful 0，`menu_kernel` 降到 priority 14、tries 15、successful 1，然后普通重启，由 depthcharge 加载那个 FIT。固件在跳进去之前把 tries 减到 0，下一次开机菜单重新是可启动里优先级最高的。另一个槽保持 priority 1。新的 `menu.kpart` 仍是 10383360 字节，sha256 `bc28358a4f965cc4f1cf0da1ff84d42814cacabdd2dff4d8509b5822945b84a6`，命令行仍是 `console=ttynull`。2026-11-02 写入 `mmcblk0p4` 并读回一致，U 盘 `/kukui-install/menu.kpart` 是同一份。Linux 根和 Android 内核槽的前 1 MiB 没变。这次写入没有改当前优先级。Linux 从这份菜单经固件启动成功。Android 黑屏十几秒后回到开发者屏幕。`/boot/kukui-phase3.log` 里，init BuildID `b7b4d9aa303cba7c8e2b9ac1bd675ee2` 在 11.4 秒放弃：`metadata`、`super`、`userdata` 的 uevent 被丢掉。命令行写的是 `androidboot.boot_devices=11230000.mmc`，init 拿平台设备路径做整段比较，eMMC 实际是 `soc/11230000.mmc`，对不上就一直跳过。内核 lzma、DTB、ramdisk 不用换。新的 `android.kpart` 只改了这一段命令行，sha256 `c0a53186ad115b4a30c276201fc9eed271f44077ecd812a13d4cf9ae3baf0523`，12529664 字节。2026-11-02 从 postmarketOS 写入 `mmcblk0p5`，读回 12529664 字节，sha256 `c0a53186ad115b4a30c276201fc9eed271f44077ecd812a13d4cf9ae3baf0523`，和这份一致。分区名仍是 `android_kernel`，父设备仍是 `11230000.mmc`。内核 lzma crc32 `f3ea1c10`，DTB crc32 `756e2f96`，ramdisk crc32 `c573f623`。这次没改分区表。菜单仍是 priority 14、tries 15、successful 1。`pmOS_kernel` 和 `android_kernel` 的优先级都是 0，下一次开机会进菜单。U 盘不在机器上，`/kukui-install/android.kpart` 仍是旧文件。从这份内核进 Android，界面起来了，Linux 也还能进。Wi-Fi 没有。`kukui-phase3.log` 里 SDIO 卡在 0.97 秒就枚举了，`ath10k_sdio` 在 66 秒读完板级文件（crc32 `d2863f91`），之后没有 `wlan0`。120 秒起 `wificond` 报 `Can't get wlan0 index`。`Vendor Hal not supported` 是这台机器本来的 nl80211 路径，不是这次坏掉的地方。第一次探测正好卡在 eMMC 大量写 userdata 的时候，SDIO 传输超时后驱动不会再试。U 盘启动时根文件系统不在这块 eMMC 上，所以以前没有这个问题。新的 `android.kpart` 只在 ramdisk 里加了开机后再探测一次的脚本，内核 lzma 和 DTB 没换，命令行仍是 `soc/11230000.mmc`。sha256 `207e2e748b157106d5382a7229e5c75869fda7fc1e7b2ebaa1473506e38f2faa`，12521472 字节，ramdisk crc32 `e2e7bd7c`。这份还没写入 `mmcblk0p5`。

## 第一次开机没有 Wi-Fi

2026-11-02 这张安装盘第一次 Ctrl+U 进了桌面，Wi-Fi 没有。再开一次就有了。正在跑的是第二次启动，`wlan0` 已经连上。

先前放进 eMMC 内核 ramdisk 的重探没有生效。这次启动的日志里，init 找不到 `/init.kukui.rc`，`/vendor/bin/kukui-wifi-reprobe.sh` 也不在这份 super 里。那份脚本即便跑起来也只看 `mmcblk0`，安静 4 秒就重载一次然后退出。U 盘启动时忙的是 `sda`，不是 eMMC。第一次开机要写 userdata。ath10k 在这期间把固件经 SDIO 送进芯片，超时之后驱动不再试，`wlan0` 就不会出现。第二次开机磁盘是安静的，同一次探测能完成：这次启动里 `ath10k_sdio` 认出 `qca6174 hw3.2`，固件 `WLAN.RMH.4.4.1-00174`，板文件 crc32 `d2863f91`。

新的脚本等第一次探测结束。已经有 `wlan0` 就退出，不去卸驱动。没有的话，看 `/data` 所在的整块盘，写下扇区连续 5 秒不变就重载 `ath10k_sdio`，最多 12 次。重载之后才出现接口，并且 `wifi_on` 不是 0，再让框架打开 Wi-Fi。`kukui-keep` 在执行 Android init 之前把脚本读进内存，等 `/vendor` 挂上之后交给 `sh`。ramdisk 里的 init.rc 过了 `FreeRamdisk` 就不在了，所以不能只靠那里定义服务。

2026-11-02 把这张 58 GiB 的 USB SD/MMC（序列号 `20120501030900000`）整盘重写了一遍，userdata 是新格式化的空分区，用来看刷写后第一次开机。内核槽读回 12505088 字节，sha256 `751887cf75db882ef09ab9794c0ef1920e633c68fc313191fc7854df734f1992`。super 读回 `76887347656c4b00509064299bf05c5f19e44572eafef68ecd672400febedb73`。`/kukui-install/android.kpart` 是 `ca25f2486e7a496ad2110bee73e3b9f6a73925e033944eddcc829d4a9e4947af`，`menu.kpart` 是 `bc28358a4f965cc4f1cf0da1ff84d42814cacabdd2dff4d8509b5822945b84a6`。内核 lzma crc32 仍是 `f3ea1c10`，DTB crc32 仍是 `756e2f96`，U 盘命令行仍是 `soc/11201000.usb/11200000.usb`。

这次 Ctrl+U 是刷写后的第一次开机：`sys.boot_completed=1` 触发时 `sys.bootstat.first_boot_completed` 还是 0。Wi-Fi 是第一次探测自己起来的。SDIO 卡在 0.97 秒枚举。可选的 pre-cal 查找从第 8 秒拖到第 95 秒才放弃，接着板文件读完，crc32 仍是 `d2863f91`。`boot_completed` 之后大约 18 秒，`wificond` 建了 `wlan0`，大约再过 40 秒连上 `34:98:b5:88:a8:a3`，11ac、5765 MHz、866 Mbps，地址 `10.0.0.115`。日志里没有 `Can't get wlan0 index`，也没有 `kukui-wifi:`。重试脚本没有跑到。`kukui-keep` 的子进程还停在 `/init`：它和 Android init 不共享 `chroot`，一直在 ramdisk 里找 `/system/bin/sh`。崩溃缓冲是空的。`stopRxFilter` 返回 code 1，以及 `multicast RX registrations are not supported`，是 ath10k 本来就不登记组播接收，连上之后没有再失败。源码里的子进程改为从 `/proc/1/root` 进入 Android 的根。正在跑的这张内核还是上面那个 sha256，没有这份改动。

同一天又把这张盘整盘抹掉重写，userdata 重新格式化。内核槽读回 12505088 字节，sha256 `dc4d17b1fabc972b7384ddcbbdc1da54466340b08b7c380da5046bdf66171ef8`。`/kukui-install/android.kpart` 读回 `162c3e5c5a89192eb9c384410cf1c99ee60bec8970861de0c166258c4ebd0d77`。super 仍是 `76887347656c4b00509064299bf05c5f19e44572eafef68ecd672400febedb73`，`menu.kpart` 仍是 `bc28358a4f965cc4f1cf0da1ff84d42814cacabdd2dff4d8509b5822945b84a6`。内核 lzma crc32 仍是 `f3ea1c10`，DTB crc32 仍是 `756e2f96`。U 盘命令行仍是 `soc/11201000.usb/11200000.usb`，没有末尾空格。

这次 Ctrl+U 仍是第一次开机：`sys.boot_completed=1` 时 `sys.bootstat.first_boot_completed` 是 0。Wi-Fi 又是第一次探测连上的。第 94 秒固件 `WLAN.RMH.4.4.1-00174`，板文件 crc32 `d2863f91`，随后 `htt-ver 3.87`。`boot_completed` 之后大约 18 秒 `wificond` 建了 `wlan0`，大约再过 9 秒 `AssocResp` 状态 0，连的是 `34:98:b5:88:a8:a3`。没有 `Can't get wlan0 index`，也没有重载 ath10k。`kukui-android phase3 wifi root` 在 5.074 秒，第二阶段 init 在 5.319 秒才打开 SELinux 策略。5.767 秒有两个名字仍是 `init` 的僵尸。日志里没有 `kukui-wifi:`。第一阶段 init 挂上 `/system` 之后 `/system/bin/sh` 就已经存在，子进程在 `switch_root` 之前进了那个根，脚本没能在第二阶段的根里执行。源码改为等 `/proc/1/exe` 变成 `/system/bin/init`，并且同一根里能看到 `ath10k_sdio.ko`，才 chroot。正在跑的内核还是 `dc4d17b1fabc972b7384ddcbbdc1da54466340b08b7c380da5046bdf66171ef8`。

同一天又整盘抹掉重写，userdata 重新格式化。内核槽读回 12505088 字节，sha256 `10dd3a4a01961c8f68a72e852cadc7206ab038217894b0db57dc3a8e589a462f`。`/kukui-install/android.kpart` 是 12509184 字节，读回 `0e3d749938414e42fe17a93a9f217e2fef9bd390f1e60f59bbab8524ea51f30d`。super 仍是 `76887347656c4b00509064299bf05c5f19e44572eafef68ecd672400febedb73`，`menu.kpart` 仍是 `bc28358a4f965cc4f1cf0da1ff84d42814cacabdd2dff4d8509b5822945b84a6`。内核 lzma crc32 仍是 `f3ea1c10`，DTB crc32 仍是 `756e2f96`。U 盘命令行仍是 `soc/11201000.usb/11200000.usb`，没有末尾空格。

这次第一次开机没有 Wi-Fi，第二次才连上。`kukui-phase3.log.prev` 是第一次开机的全文。第 97.7 秒 `ath10k_sdio` 报 `bmi communication timeout`，写设备返回 `-110`，板数据没写进去，`could not probe fw (-110)`。没有 `firmware ver`，没有 `wlan0` 注册。`wificond` 多次 `Failed to setup iface`。日志里没有 `kukui-wifi:`。子进程从 9 秒起就能打开 `/system/bin/sh`（在 `dm-0` 上），但 `/vendor` 是 init 另开的挂载命名空间里的 `dm-1`，模块文件一直打不开，所以没有 chroot，也没有 `wifi root`。第二次开机的 `kukui-phase3.log` 记到 604 秒，仍然没有 `wifi root`。只认 `second_stage` 不够。源码在认到 `second_stage` 之后先 `setns` 进 `/proc/1/ns/mnt`，再 chroot。新的 `kukui-keep` sha256 `af5530760371f4ae2ede95fe64f5bc8ae82f1bf32ce746f5268561ad2a29a24d`，`kukui-keep-emmc` 是 `8eee3481f0bc70f8b64853107dc54d2901f63fa04668bd9e90b32134eb04a6ef`。

同一天又整盘抹掉重写，userdata 重新格式化。内核槽读回 12505088 字节，sha256 `0eb96b29f61c6d8e8e1e8b94ca3ba00c3feb04a6ed6f085a290949560aa1127d`。`/kukui-install/android.kpart` 是 12505088 字节，读回 `71057637e89b3223cfa1cdcc17392c009bc81a9ca8788c6bb896622ac609c0ed`。super 仍是 `76887347656c4b00509064299bf05c5f19e44572eafef68ecd672400febedb73`，`menu.kpart` 仍是 `bc28358a4f965cc4f1cf0da1ff84d42814cacabdd2dff4d8509b5822945b84a6`。内核 lzma crc32 仍是 `f3ea1c10`，DTB crc32 仍是 `756e2f96`。U 盘命令行仍是 `soc/11201000.usb/11200000.usb`，没有末尾空格。eMMC 那份命令行末尾仍有一个空格。

这次 Ctrl+U 是第一次开机，桌面起来之后 Wi-Fi 可用。`sys.boot_completed=1` 在 150.6 秒，当时 `sys.bootstat.first_boot_completed` 仍是 0。第二阶段 init 在 5.271 秒打开 SELinux 策略。`kukui-android phase3 wifi mnt` 在 6.063 秒，`wifi root` 在 6.111 秒，说明子进程进了 init 的挂载命名空间并完成 chroot。第 94.7 秒固件 `WLAN.RMH.4.4.1-00174`，板文件 crc32 `d2863f91`，没有 `-110`。`wlan0` 在 191.5 秒连上 `34:98:b5:88:a8:a3`。日志里没有 `kukui-wifi:`。6.120 秒 pid 2935 以状态 1 退出，名字仍是 `init`：`/system/bin/sh` 的解释器是 `/system/bin/linker64`，它指向 runtime APEX，这时 APEX 还没挂上，`exec` 失败，脚本没有启动。这次 Wi-Fi 是第一次探测自己完成的。源码改为 `exec` 失败后继续等解释器，最多 180 秒。在已经开机的系统里另开挂载命名空间，把 runtime APEX 盖住：第一次 `exec /system/bin/sh` 失败，3 秒后揭开，同一条管道里的脚本执行成功，写出 `kukui-wifi-test-ok`。正在运行的系统本身没有受影响。

同一天又整盘抹掉重写，userdata 重新格式化。内核槽读回 12505088 字节，sha256 `2eae2addef3de595bc85289db2b2e28aa66c8fa07fdefc381d63d29aaaad6032`。`/kukui-install/android.kpart` 读回 `be279614781d201821531d1298177757fe8ffd74dddb32ec4b97631564678c99`。super 仍是 `76887347656c4b00509064299bf05c5f19e44572eafef68ecd672400febedb73`，`menu.kpart` 仍是 `bc28358a4f965cc4f1cf0da1ff84d42814cacabdd2dff4d8509b5822945b84a6`。内核 lzma crc32 仍是 `f3ea1c10`，DTB crc32 仍是 `756e2f96`。U 盘命令行仍是 `soc/11201000.usb/11200000.usb`，没有末尾空格。这次 Ctrl+U 是第一次开机。设置向导里没有 Wi-Fi，手动跳过之后，进桌面时 Wi-Fi 已经出现。`sys.boot_completed=1` 在 150.1 秒，当时 `sys.bootstat.first_boot_completed` 仍是 0。第二阶段 init 在 5.086 秒打开 SELinux 策略。`wifi mnt` 在 6.057 秒，`wifi root` 在 6.061 秒。6.070 秒 `wifi sh 2`：`exec /system/bin/sh` 返回 `ENOENT`，因为 runtime APEX 还没挂上。95.9 秒审计里已经有 `comm=sh`。第 96.0 秒打出固件 `WLAN.RMH.4.4.1-00174`，接着 BMI 超时，`could not probe fw (-110)`，没有 `wlan0`。150.1 秒 `boot_completed` 时 `wificond` 报 `Can't get wlan0 index`。151.0 秒 `kukui-wifi: wlan0 missing after the first probe`。随后 `kukui-wifi: reloading ath10k`。重载后的固件仍是 `WLAN.RMH.4.4.1-00174`，板文件 crc32 `d2863f91`，194.7 秒 `htt-ver 3.87`。接着是 `kukui-wifi: wlan0 up` 和 `kukui-wifi: framework wifi enabled`。312.4 秒 `wlan0` 连上 `34:98:b5:88:a8:a3`。

## 两块盘

这台 Krane sku176 没有 SD 卡槽。阶段 0 量到的内置盘是 eMMC `mmcblk0`，116.5 GiB，父设备 `11230000.mmc`。当时的分区是：

| 分区 | 起始扇区 | 扇区数 | 名称 |
| --- | --- | --- | --- |
| mmcblk0p1 | 8192 | 65536（32 MiB） | `pmOS_kernel` |
| mmcblk0p2 | 73728 | 1048576（512 MiB） | `pmOS_boot` |
| mmcblk0p3 | 1122304 | 243154911 | `pmOS_root` |

外置盘是插在读卡器里的 U 盘。内核里它走 USB 2.0 的 xHCI `11200000.usb`，控制器是 `11201000.usb`，名字是 `sd*`，不是 `mmcblk`。Android 只给 `androidboot.boot_devices` 这条路径建 `/dev/block/by-name`。现在这条路径是 USB，所以即便以后 eMMC 上出现同名的 `super`，从 U 盘启动时也不会去挂它。

U 盘上的 Android 几何和 eMMC 上的 postmarketOS 不是同一张表。内核槽仍从扇区 8192 起、长 65536。后面是 `pmOS_boot`、8 GiB 的 `super`、`metadata`、`misc`，`userdata` 占到盘尾。不能把 U 盘整盘 `dd` 到 eMMC 上：容量不一样（U 盘大约 119 GiB，eMMC 是 116.5 GiB），分区名和文件系统也不是同一套。

## InstallAndroid 为什么会把 SD 卡当成 eMMC

`third_party/InstallAndroid-lineage-24` 是给 Trogdor（高通 SC7180）用的图形安装器，说明书写的是从 Live USB 把 LineageOS 装进 eMMC 或 NVMe。这个目录里只有界面。真正写盘的是 init 服务 `install_to_emmc`，脚本不在这里，所以下面只判断选盘，不判断它怎么拷字节。

`MainActivity.scanDrives()` 的规则是：

1. 从 `/proc/mounts` 里找挂在 `/metadata` 或 `/data` 上的块设备。动态分区实际挂的是 `/dev/block/dm-*`。名字不是 `mmcblk` 也不是 `nvme` 时，它只是去掉末尾的数字。`dm-5` 会变成 `dm-`。读不到挂载时，启动盘直接写成 `sda`。
2. 启动盘的名字以 `mmcblk` 或 `nvme` 开头，并且 `/sys/class/block/<盘>/removable` 不存在或者是 `0`，就认定已经从内置盘启动，安装按钮消失。
3. 安装目标按写死的顺序挑：`mmcblk1`、`mmcblk0`、`nvme0n1`。存在、又不是上一步那个启动盘，就收进列表。真正擦掉的是列表里的第一块。

它不看控制器路径，也不看 `removable` 是不是目标盘的属性。Trogdor 上内置 eMMC 和外置 microSD 都是 `mmcblk`，谁先被探测谁占 `mmcblk0`。SD 控制器的 `removable` 经常是 `0`（设备树没把它标成可拔插时，内核就这么报）。于是会出现两种和用户记得的一样的结果：从 SD 启动时，SD 被当成“已经装在内置盘上”；从 USB 启动、挂载又落在 device-mapper 上时，排在前面的那块 `mmcblk` 被标成内置盘，这块可以就是 SD 卡。两种都没有核对 SDHCI 和 eMMC 控制器。

Kukui 没有 SD 卡槽，所以上面那个“SD 被当成 eMMC”的具体错法在这台上不会原样出现。U 盘是 `sd*`，eMMC 是唯一的 `mmcblk0`。按这段代码，从 U 盘启动、`/data` 又在 `dm-*` 上时，它会选中 `mmcblk0`，而那确实是 eMMC。这不是可以拿来用的理由。它仍然不检查 `11230000.mmc`，也不拒绝 `11201000.usb`。选错盘的方式和 Trogdor 不同，后果一样：擦掉不该擦的那块。这个项目不能直接用，也不值得在它的选盘逻辑上小改，选盘是错的那一层。

## 从 U 盘安装

可以做，而且应该从 U 盘上已经启动的 Android 来做，不要从正在使用的那块盘上装它自己。还没写安装器。真要做的时候，目标盘只认 sysfs：

- 启动盘的设备路径里必须有 `11201000.usb` 或 `11200000.usb`。这是当前这次启动的盘，只读，不作为目标。
- 目标必须是 `mmcblk0`，并且 `/sys/class/block/mmcblk0` 的设备路径里有 `11230000.mmc`，`removable` 是 `0`。
- 路径里带 `11201000.usb`、`11200000.usb`，或者是工作站上那块 YMTC，直接退出。
- 不按 `mmcblk` 的序号挑，也不把“不是启动盘的第一块 mmc”当成内置盘。

只装 Android、不要 postmarketOS 时，eMMC 的分区表换成和 U 盘同一套角色，大小按 116.5 GiB 重算。`super` 维持 8 GiB。`userdata` 用剩下的空间。内核槽仍是带 ChromeOS 属性的 FIT（priority 15、tries 15、successful 1），板名 `mt8183`，压缩 lzma，里面只放 `mt8183-kukui-krane-sku176.dtb`。这条 FIT 的命令行把 `androidboot.boot_devices` 改成 `11230000.mmc`。改过的内核只放在 eMMC 上。U 盘上的恢复镜像继续用 USB 那条命令行，否则 U 盘和以后要开的 gadget 会抢 `11201000.usb`，从 U 盘也找不到自己的 `super`。

这一步会删掉 eMMC 上的 postmarketOS。写之前先把分区表和 `mmcblk0p1` 拷到别的盘上，和路线图里阶段 8 的要求一样。写完用 Ctrl+D 进内置盘，Ctrl+U 仍应进 U 盘。这两次启动都还没有做。

## 两个系统都在 eMMC 上

depthcharge 不会在内置盘上列出两个系统。开发者屏幕里，Ctrl+D 或超时进入优先级最高的那一个内核槽，Ctrl+U 进入 U 盘。可拆卸设备的固件菜单能用音量键和电源键翻页，那些页面是语言、开发者选项和“从外部磁盘启动”，不是 Android 和桌面 Linux 的列表。所以“两个系统都在 eMMC 上，开机时点一下选哪个”不能靠原厂界面，也不能靠再插一张 U 盘。

现成的项目对得上哪一块：

| 项目 | 能用的部分 | 对不上的部分 |
| --- | --- | --- |
| `depthchargectl`、`cgpt` | postmarketOS 里就有。在已经启动的系统里改内核槽优先级，然后重启进另一个系统 | 没有开机画面。要先进一个系统才能选 |
| `third_party/InstallAndroid-lineage-24` | 安装按钮和进度条的样子 | 选盘是错的，而且只考虑装一个 Android，会擦掉 Linux |
| MrChromebox 的全量 UEFI | edk2 可以做图形启动菜单 | 要换只读固件。这台机器不刷 UEFI |
| `kexecboot` | 帧缓冲上的选单，用键盘选内核再 kexec | 没有 Goodix，没有 `mtk-drm`，年头久了，不能拿来编进这颗 FIT |
| U-Boot 的 `bootmenu`，作为 FIT 载荷而不是去刷 ROM | 音量键可以绑成上下 | 没有 Krane 的现成菜单，触摸也不在 U-Boot 里 |

没有一个项目可以原样或只改几行就在这台上提供触摸或音量键的双系统菜单。

这台机器上，触摸是 Goodix `27C6:0E30`，Android 和 postmarketOS 都已经在用。底座接上时，Hammer 键盘也能当选单键。侧边音量键和电源键在固件菜单里能用。Krane 不走 Jacuzzi 那种 `gpio-keys`。`mt8183-kukui-krane.dtsi` 里的 `google,cros-ec-keyb-switches` 会问 EC 支持哪些按键，音量加减和电源就在这里，驱动编进了内核。底座键盘不是标配，选单不依赖它。没有键盘时，点屏幕上的按钮直接进入；音量加第一次亮 Android，再按一次进入，音量减对 Linux 同样；电源键在已经亮起一项时进入那一项。触摸在面板上，不在键盘盖上。

菜单用已经验证过的 `6.18.28-mt81-kukui2`。initramfs 用 `mtk-drm` 在 DSI 上画两个选择，读 Goodix，底座接上时再读 Hammer 键盘。选中之后不 kexec：改一次 GPT 优先级再重启，由 depthcharge 加载对应的 FIT。postmarketOS 用它原来的内核槽。Android 用 `androidboot.boot_devices=soc/11230000.mmc` 的那份 FIT。U 盘继续是写坏之后的 Ctrl+U 退路。

## 缩小根分区由安装器来做

缩小由从 U 盘启动的 Android 安装器来做。用户在确认画面上看到根会留多大、Android 的数据分区还剩多大，点一次即可。postmarketOS 的根从扇区 1122304 铺到盘尾，Android 的 `super`（8 GiB）、`metadata`、`misc`、`userdata` 和多出来的内核槽都放在这块根的后面。根保持现在的大小时，后面没有空位。

从 U 盘启动时，这条 Android 的 `boot_devices` 只认 USB，eMMC 上的 ext4 没有挂上，可以离线缩小。安装器使用系统里已有的 `e2fsck`、`resize2fs` 和 `sgdisk`。它先读已用块数。新的根至少是已用空间再加 2 GiB，并且按 1 GiB 向上取整。上限是还要留下 8 GiB 的 `super`、两个 32 MiB 内核槽、64 MiB 的菜单文件分区、16 MiB 的 `metadata`、4 MiB 的 `misc`，以及至少 8 GiB 的 `userdata`。确认画面给出这个范围，输入框里先放 16；16 低于下限时放下限，高于上限时放上限。用户可以改成范围内的任意整数 GiB，点计算后看到对应的 Android 数据分区大小，再点安装。空闲空间放不下上述固定部分时，安装器拒绝双系统，只保留“只装 Android”。

只装 Android 时不缩小。安装器按前面那一节换掉整张分区表，postmarketOS 的根不保留，菜单也不写。

缩小的顺序是先文件系统、后分区表。`e2fsck -f` 失败就停，不动分区。`resize2fs` 完成之后，分区仍然比文件系统大，postmarketOS 还能从原来的内核槽启动。然后才把 `mmcblk0p3` 收到和文件系统一样大（1 MiB 对齐）。断电如果发生在 `resize2fs` 进行中，根有损坏的可能。内核槽只有 32 MiB，安装器在动手之前把它和分区表拷到 U 盘的 `pmOS_boot` 上。这不是整块根的副本。根上已经装过的软件靠 `e2fsck` 和“先缩文件系统”来保，保不住的那一种就是缩到一半断电。

默认把根留成 16 GiB 时，后面的新分区从扇区 34676736 起，都按 1 MiB 对齐：

| 分区 | 扇区数 | 名称 | 作用 |
| --- | --- | --- | --- |
| 原 p1 | 65536 | `pmOS_kernel` | 原来的 postmarketOS FIT，字节不动。优先级最后改成 1 |
| 原 p2 | 1048576 | `pmOS_boot` | 不动 |
| 原 p3 | 33554432（16 GiB） | `pmOS_root` | 缩小后的 ext4 |
| 新 | 65536 | `menu_kernel` | 菜单 FIT。写完并读回之后优先级设为 15 |
| 新 | 65536 | `android_kernel` | eMMC 用的 Android FIT，`boot_devices=11230000.mmc`。优先级 1，给 U 盘恢复时直接抬优先级用 |
| 新 | 131072（64 MiB） | `bootmenu` | ext2。当时为 kexec 放了两份内核和命令行，现在的菜单不读这里 |
| 新 | 16777216（8 GiB） | `super` | 和 U 盘同一份 super 的字节 |
| 新 | 32768（16 MiB） | `metadata` | ext4 |
| 新 | 8192（4 MiB） | `misc` | 空 |
| 新 | 到备份 GPT 之前 | `userdata` | f2fs，第一次启动再扩到分区尾 |

`menu_kernel` 和 `android_kernel` 的类型 GUID 用 ChromeOS 内核 `FE3A2A5D-4F32-41A7-B725-ACCC3285A309`。depthcharge 按优先级挑，不看分区是不是紧挨着盘头。所以这两个槽可以放在根的后面。

## 菜单和系统分区同一次写入

要。双系统安装器在同一次运行里写完空出来的分区、Android 的 super、两份内核，以及菜单 FIT。菜单 FIT 事先在工作站上编好，放在 U 盘镜像里，安装器只负责拷贝和设优先级。设备上不编译。

优先级是提交点，放在最后。在它改掉之前，Ctrl+D 仍然进原来的 postmarketOS。super、菜单 FIT、Android FIT 都读回一致之后，才把 `menu_kernel` 设成 priority 15、tries 15、successful 1，把 `pmOS_kernel` 降到 priority 1。菜单坏了的时候，从 U 盘启动，用 `cgpt` 把 `pmOS_kernel` 或 `android_kernel` 抬回 15，depthcharge 就能绕过菜单直接进其中一个系统。

`bootmenu` 里的内核和命令行是当时为 kexec 准备的。现在的菜单不读它们，depthcharge 直接启动 `pmOS_kernel` 或 `android_kernel` 里的 FIT。这些文件留在分区上。

只装 Android 的那条路径不写 `menu_kernel`，也不留 `pmOS_root`。

## 实现步骤

1 到 4 的程序在 U 盘上。eMMC 的 Linux 根已经是 40 GiB，后面的分区表也建好了，但 super 和启动优先级还没写完，Ctrl+D 仍进 postmarketOS。下一步是先把 postmarketOS 正常关机，再 Ctrl+U 这张新 U 盘。打开“安装到 eMMC”，进度在窗口中间。双系统仍填 40，点计算，再点安装。安装过程不要退出，不要关机。

1. 两份 FIT 都用现在这张 U 盘内核里的同一段 lzma（crc32 `f3ea1c10`）和 `mt8183-kukui-krane-sku176.dtb`（crc32 `756e2f96`）。eMMC 那份只把 `androidboot.boot_devices` 换成 `11230000.mmc`，init 换成只认 `11230000.mmc` 的 `kukui-keep`。菜单那份是同一个内核加上只含选单的 initramfs。fbdev 留着，这样才有 `/dev/fb0`；控制台改到 `ttynull`，避免日志盖住按钮。选单画“Android”和“Linux”。initramfs 里要有 `evdev.ko`，否则没有 `/dev/input/event*`，音量键和触摸都到不了选单。没有底座键盘时用触摸、音量键和电源键。kexec 在这台上进不去系统，菜单改为改一次 GPT 再重启，由 depthcharge 加载选中的 FIT。两份 FIT 和菜单用的是同一份 sku176。这些文件在 U 盘的 `/kukui-install`，不在内核槽。
2. 安装器是 vendor 里的“安装到 eMMC”，包名 `org.lineageos.kukuiinstaller`，加上 root 服务 `/vendor/bin/kukui-installd`。`e2fsck`、`resize2fs`、`sgdisk`、`mke2fs`、`make_f2fs` 用系统里已有的，没有再塞静态副本。镜像里没有 `dumpe2fs`，大小用 `tune2fs -l` 算。界面先读 sysfs：启动盘的路径里要有 `11201000.usb` 或 `11200000.usb`，`mmcblk0` 的路径里要有 `11230000.mmc`，`removable` 要是 0。对不上，两个按钮不开。
3. 只装 Android 的确认画面写明 eMMC 上的 postmarketOS 会被删掉。点了安装才备份 `mmcblk0p1` 和分区表到 U 盘，换分区表，写入 eMMC 专用 FIT、super、metadata、misc，把 userdata 格式化成 f2fs，读回 FIT 和 super。U 盘内核槽不写。
4. 两个系统都留的确认画面可以改 Linux 根分区的 GiB，范围是已用加 2 GiB 到仍能留下至少 8 GiB Android 数据的上限，输入框默认 16。点计算才更新数据分区大小，点安装才写入。eMMC 上现有内核的前一段必须和安装器里的 postmarketOS 副本一致（sha256 `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e`），否则这条路径拒绝。通过之后 `e2fsck -f`、`resize2fs`、缩小 `mmcblk0p3`、按上一节的表建新分区，写入菜单 FIT、Android FIT、`bootmenu` 里的两套内核和命令行、super，格式化 metadata 和 userdata。每一段读回。全部一致之后才把 `menu_kernel` 设成 priority 15，把原来的 `pmOS_kernel` 降到 priority 1。
5. 还没做。安装器写完会停在“拔掉 U 盘再重启”，它自己不重启。Ctrl+D 进菜单、点 Android、点 Linux，以及再插上 U 盘 Ctrl+U 仍进这张恢复镜像，都要在实机上看过。
