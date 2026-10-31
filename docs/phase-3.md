# 阶段 3：亮屏

2026-10-31 结束。路线图在 [roadmap.md](roadmap.md)。用阶段 2 的内核 `6.18.28-mt81-kukui2`，在 U 盘上启动第一份 Android。不写 eMMC，不启用 USB gadget，不测 Wi-Fi、蓝牙、音频和休眠。

源码树是 `/run/media/alpha/YMTC/lineage-23.2`。板级文件在这个仓库的 `device/google/kukui`，逐个文件链进源码树。`system/core/libcutils/ashmem-dev.cpp` 里已经先做 `F_GET_SEALS`，这一段不再改那份文件。CFI 和 shadow call stack 保持阶段 2 的 `=y`。后面两次只重编内核，分别打开 f2fs 安全标签和 dm-verity，版本字符串没变。

## 产品

`lunch lineage_kukui-trunk_staging-userdebug`。平板、仅 Wi-Fi。不设 `TARGET_INITIAL_BRINGUP`。

用户看见的画面是 1920×1200，密度 240。DRM 扫描仍是 `1200x1920@60.00`。`ro.surface_flinger.primary_display_orientation=ORIENTATION_270`，和阶段 0 里设备树 `rotation = <270>` 一致。不把刷新率写成 61。`vendor.hwc.drm.device=/dev/dri/card0`，名字是 `DSI-1`。`init.kukui.rc` 在合成器之前解开 `vtcon0` 和 `vtcon1`。

图形是 Mesa Panfrost、minigbm `generic`、AIDL `drm_hwcomposer`。Vulkan 关掉。`trunk_staging` 会把 `RELEASE_SM_OPEN_DECLARED_PASSTHROUGH_HAL` 设为 true，minigbm 的 APEX 随之删掉 vendor 里的 `mapper.minigbm_upstream`。`device.mk` 在继承 mainline 之后把这项 soong 配置写回 false，mapper 留在 vendor。lunch 目标仍是 `trunk_staging`。

不写 `binder.impl=rust`，不写 `rw`，不写 `androidboot.boot_devices=any`。KeyMint 和 Gatekeeper 用软件实现，清单本身几乎是空的，这两个 HAL 的片段在各自的 APEX 里。FCM 202604 不收 HIDL manager 1.2 和 token 1.0，所以不把它们写进设备清单。

## 命令行

阶段 1 的命令行加上 SELinux 和硬件名。`depthchargectl` 自己加 `kern_guid=%U`。

```text
lsm=landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,bpf console=tty0 loglevel=7 deferred_probe_timeout=30 androidboot.selinux=permissive androidboot.hardware=kukui androidboot.boot_devices=soc/11201000.usb/11200000.usb printk.devkmsg=on drm_client_lib.active=none
```

`11200000.usb` 是阶段 1 里 U 盘所在的 xHCI，它的平台设备路径是 `soc/11201000.usb/11200000.usb`。init 用整段路径做比较，只写最后一节不会建立 `/dev/block/by-name`。eMMC 的 `11230000.mmc` 不用。`lsm=` 里 selinux 必须在 bpf 前面。bpf 的 `getprocattr`/`setprocattr` 没实现时直接返回 EINVAL，而且它排在前面就会截住调用，init 的 `setexeccon` 到不了 SELinux。`security=` 和 `lsm=` 同时出现时内核会忽略 `security=`，所以 SELinux 写在 `lsm=` 里。阶段 2 没有启用 SELinux。这一段加上之后才会启用，并且是 permissive。`drm_client_lib.active=none` 不让内核的 fbdev 客户端打开 `/dev/dri/card0`。6.18 里这个客户端在 `drm_client_init()` 时就成为 DRM master，解开 vtcon 不会放开它。

## 分区

只改 U 盘 `sdb3` 往后。`sdb1`（`pmOS_kernel`）和 `sdb2`（`pmOS_boot`，日志分区）不动。磁盘 122167296 扇区，每扇区 512 字节。原来的 `sdb3` 从扇区 1122304 到 122167263（不含），后面空 33 个扇区。2026-10-30 写入前核对的表现状：

| 分区 | 起始扇区 | 扇区数 | 名称 |
| --- | ---: | ---: | --- |
| sdb1 | 8192 | 65536 | pmOS_kernel |
| sdb2 | 73728 | 1048576 | pmOS_boot |
| sdb3 | 1122304 | 121044959 | pmOS_root |

计划写成：

| 分区 | 起始扇区 | 扇区数 | 大小 | 名称 |
| --- | ---: | ---: | --- | --- |
| sdb1 | 8192 | 65536 | 32 MiB | pmOS_kernel，不改 |
| sdb2 | 73728 | 1048576 | 512 MiB | pmOS_boot，不改 |
| sdb3 | 1122304 | 16777216 | 8 GiB | super |
| sdb4 | 17899520 | 32768 | 16 MiB | metadata |
| sdb5 | 17932288 | 8192 | 4 MiB | misc |
| sdb6 | 17940480 | 104226783 | 约 49.7 GiB | userdata |

起始扇区都是 4 MiB 对齐。userdata 的结尾停在原来 `sdb3` 的结尾，不占用末尾 33 个扇区。fstab 按 GPT 名找 super、metadata、userdata、misc，不写 `sda`。userdata 在第一阶段挂载，文件系统是 f2fs，空分区由 `formattable` 格式化。这颗内核没有 `CONFIG_BLK_INLINE_ENCRYPTION`，fstab 不写 inline crypt。

super 是动态分区，8 GiB。system、vendor、product、system_ext、system_dlkm、vendor_dlkm 是 erofs。`sdb3` 上原来的 postmarketOS 根是装 eMMC 之前的那份副本，eMMC 上还有一份。删掉 U 盘这份之前，镜像必须已经编出来。

写入脚本是 `bringup/phase3/write-usb.sh`。它先打印分区表，再要求磁盘走 USB、`sdb1` 的名字是 `pmOS_kernel`、工作站的根不是 `sdb`。eMMC 不在这个脚本里。

## 开机模块

面板、`mtk-drm`、Panfrost、EC 键盘已经编进内核。erofs、ext4、f2fs、device-mapper、zram、loop 也是。ramdisk 里另加的是模块，因为缺了它们就没有磁盘或没有界面：

- `usb-storage`。阶段 1 第一次 Ctrl+U 没有它，读卡器枚举出来了，磁盘没有出现。
- `xfrm_user` 和 `xfrm_algo`。`netd` 没有它会退出，zygote 跟着重启。
- nftables 以及它们的依赖，包括 `ipv6`。`netd` 要这些。
- Goodix 触摸：`i2c-hid`、`i2c-hid-of`、`i2c-hid-of-goodix`、`hid-generic`、`hid-multitouch`。
- `fuse`。APEX 和存储要用，它是模块。

一开始是 30 个未压缩模块，约 2.6 MiB。后来补上 iptables 匹配，以及 `af_key`、`nfnetlink_log`、`dummy`、`configs`。现在 `modules.load` 是 54 行。目录名是 `6.18.28-mt81-kukui2`，和 `uname -r` 一致。不加载 USB gadget、ath10k 和声卡模块。

`kukui-keep` 是 ramdisk 里的 `/init`。它加载 `usb-storage`，只在 `sd*` 上找 `PARTNAME=pmOS_boot` 和 `super`，把 kmsg 写到 `/bootlog/kukui-phase3.log`。读 kmsg 和写盘是两个进程：读进程只往 1 MiB 管道里送，写进程才 `fsync`。这样格式化同一根 U 盘时，卡住的 `fsync` 不会停掉对 printk 环的读取。父进程卸掉 `/bootlog`、`/kukui-proc`、`/kukui-sys`、`/dev`，再执行 `/init.android`。不喂看门狗。写进程仍握着日志文件，所以第二阶段不能再挂这块分区。

zygote 和 surfaceflinger 的用户空间日志不进 kmsg。`init.kukui.rc` 在 `on fs` 里、`mount_all` 之前挂上 `pmOS_boot`，用 logcat 写 `/kukui-phase3-logcat.txt`。keystore 的崩溃原因只进 logd，不进 kmsg。

## 已写入

2026-10-30 写入 U 盘。写入前的分区表就是上面那张。`sdb1` 和 `sdb2` 的起止没变。新表：

| 分区 | 起始扇区 | 扇区数 | 名称 |
| --- | ---: | ---: | --- |
| sdb1 | 8192 | 65536 | pmOS_kernel |
| sdb2 | 73728 | 1048576 | pmOS_boot |
| sdb3 | 1122304 | 16777216 | super |
| sdb4 | 17899520 | 32768 | metadata |
| sdb5 | 17932288 | 8192 | misc |
| sdb6 | 17940480 | 104226783 | userdata |

`super.raw` 8,589,934,592 字节，sha256 `526d9df8fae823f84f17b604ae5dbbb04c3f18e30d8bd8009cd73b333576a741`。第一份 FIT 12,320,768 字节，sha256 `735fc71f10a085646e920ffc2e23b36629de3bc81e784544ea82e3625ad6da35`。它能进内核，但停在 `kukui-android phase3 no boot partition`。

`kukui-keep` 把 sysfs 挂在 `/kukui-sys`，找分区时却去读 `/sys/class/block`。ramdisk 里的 `/sys` 是空目录，所以 45 秒里每次都找不到 `pmOS_boot`。分区表本身还在。修正后只换了内核槽。新 FIT 仍是 12,320,768 字节，读回 `sdb1` 的 sha256：

```text
c4a94d0b1c12226b540124c2db2fe5976d2612c250a002c375af1bfe203ad5ef
```

FIT 里的命令行：

```text
kern_guid=%U console=tty0 loglevel=7 deferred_probe_timeout=30 security=selinux androidboot.selinux=permissive androidboot.hardware=kukui androidboot.boot_devices=11200000.usb printk.devkmsg=on
```

第二次 Ctrl+U 几秒就回到选盘界面。屏幕停在 `init first stage started` 之后：`sda` 已经出现，`sda2` 也挂上了，然后是 `/dev/block/by-name/super: No such file or directory`、`Failed to create devices required for first stage mount`、`InitFatalReboot: signal 6`。`ReadFstabFromDt` 失败是预期的，fstab 在 ramdisk 里。`pmOS_boot` 上没有日志，重启发生在回写之前。

init 只给 `androidboot.boot_devices` 与块设备最近的平台节点完全一致时建立 `/dev/block/by-name`。阶段 1 的路径是 `/devices/platform/soc/11201000.usb/11200000.usb/...`，去掉 `/devices/platform/` 之后是 `soc/11201000.usb/11200000.usb`。上一份只写了 `11200000.usb`，对不上，所以 `super` 的符号链接没有建立。`modules.dep` 里没有依赖的行带了尾部空格，init 把空字段当成模块路径，所以 `hid-generic` 等加载失败。这和 Gru 同一类，但不是这次重启的原因。

第三次只换了内核槽。新 FIT 仍是 12,320,768 字节，读回 `sdb1` 的 sha256：

```text
cde488fa6f1b8e9ac94bf5da13019d51791be69d7970ebed2627aacb5965e469
```

命令行：

```text
kern_guid=%U console=tty0 loglevel=7 deferred_probe_timeout=30 security=selinux androidboot.selinux=permissive androidboot.hardware=kukui androidboot.boot_devices=soc/11201000.usb/11200000.usb printk.devkmsg=on
```

没有 `binder.impl=rust`，没有 `root=`。`kukui-keep` 在交出 init 之前会把日志刷到盘上。super、metadata、misc、userdata 没动。这次写入时平板不在网上，eMMC 没有重新核对。上一份写入之后它仍是同一次启动：`boot_id` `7ed1eb4a-7f21-4ab7-84e1-bb227cce9775`，根 `/dev/mmcblk0p3`，`uname` `6.18.28-mt81`，`/boot/vmlinuz.kpart` 的 sha256 `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e`。

第三次 Ctrl+U 大约 15 秒回到选盘界面。日志在 `pmOS_boot/kukui-phase3.log`，副本是 `bringup/phase3/kukui-phase3.log`，sha256 `9198f5a35e6c0015cc4f99f9ff0d5e6ac084416616cfeac0efbe57834c594087`。29 个模块都加载了。六个逻辑分区挂上了，`/system` 的 erofs 挂载成功，第二阶段 init 也起来了。随后 `setexeccon('u:r:vendor_init:s0')` 和 `u:r:ueventd:s0` 都是 `Invalid argument`，`apexd-bootstrap` 读不到当前安全上下文，init 执行 `reboot,bootloader,bootstrap-apexd-failed`。照片上的 `by-name/misc` 是关机时 bootstat 的重试，不是这次重启的原因。

`CONFIG_LSM` 里 bpf 在 selinux 前面，`security=selinux` 只把 SELinux 追加到末尾。bpf 给每个 LSM 钩子都挂了一个默认函数，`getprocattr` 和 `setprocattr` 的默认返回值是 EINVAL，而且调用到第一个钩子就停。init 写 `/proc/thread-self/attr/exec` 时到不了 SELinux。策略里的 `vendor_init` 本身是合法上下文。

第四次只换了内核槽。命令行改成 `lsm=`，selinux 放在 bpf 前面，不再写 `security=`。新 FIT 仍是 12,320,768 字节，读回 `sdb1` 的 sha256：

```text
bb90b712899304595cd2068c12cd1b5f8f09450efb2281693cc48e8efa9f0f34
```

命令行：

```text
kern_guid=%U lsm=landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,bpf console=tty0 loglevel=7 deferred_probe_timeout=30 androidboot.selinux=permissive androidboot.hardware=kukui androidboot.boot_devices=soc/11201000.usb/11200000.usb printk.devkmsg=on
```

super、metadata、misc、userdata 没动。这次写入时平板不在网上，eMMC 没有重新核对。

第四次 Ctrl+U 大约几秒回到选盘界面。日志副本是 `bringup/phase3/kukui-phase3.log`，sha256 `6ebdf82c0e4dbae493126f22b84f9b6e08273d768862df2172faecaba5490aac`。`lsm=` 生效：`ueventd` 起来了，`apexd-bootstrap` 退出状态 0，八个 APEX 挂上，其中包括软件 KeyMint。文件的最后一行是 `crash_dump64` 对 `u:r:keystore:s0` 的 ptrace，permissive。没有 `InitFatal`，也没有 logcat。`/data` 和 `/metadata` 的超级块仍然无效，第一阶段把可格式化分区跳过了。

`keystore2` 是 `early_hal`，工作目录是 `/data/misc/keystore`，`critical window=0`。这个目录要到 `post-fs-data` 才建，而 `early_hal` 在那之前。打开数据库失败会直接 abort。崩溃超过四次、`sys.boot_completed` 还没置上，init 就重启进选盘界面。这次 `mount_all` 带了 `--late`。fstab 里的 userdata 和 metadata 没有 `latemount`，所以第二阶段什么都没挂，空分区也没被格式化。

`ReadFstabFromDt`、没有 vbmeta、没有 `/odm`、Panfrost 注册 cooling device 失败、APEX 退回缓冲 I/O、内核域写日志的 permissive AVC，都不是这次重启的原因。`init.mainline.usb.rc` 缺失是因为这一阶段关掉了 USB gadget，mainline 的 rc 仍会 import 它；把那份完整脚本装上会启用 gadget，所以留着这个警告。`ro.vendor.init_dev_config.path` 没设，对应的是 cuttlefish 的配置程序，不设它是对的。`ueventd` 把 `ueventd.kukui.rc` 读了两遍，因为 `ro.board.platform` 和 `ro.hardware` 都是 `kukui`，规则相同。

修正写在 vendor 里，所以换了 super，没有换内核槽，也没有重分区。`metadata` 改到 `userdata` 前面，密钥目录先挂上。`on fs` 先挂日志分区并启动 logcat，再启动 `vendor.keymint-default`，然后 `mount_all` 不带 `--late`。`on post-fs` 在 `early_hal` 之前创建 `/data/misc/keystore`。新的 `super.raw` 仍是 8,589,934,592 字节，读回 `sdb3` 的 sha256：

```text
b60a1f87635ad8a8cbc22d6f61365be4969f22b7bab24ba9e249765469bd36c5
```

内核槽仍是 `bb90b712899304595cd2068c12cd1b5f8f09450efb2281693cc48e8efa9f0f34`。metadata、misc、userdata 仍是空的，留给这次启动格式化。写入时平板不在网上（`10.0.0.117` 没有路由），eMMC 没有重新核对。

第五次 Ctrl+U 比上次多了几秒，仍然回到选盘界面。没有 `kukui-phase3-logcat.txt`。kmsg 副本 sha256 `fd2f949264d149a2f6d00f8d7dfa2babee6623632cfcb5194a2262739ddce6bb`。新的 `init.kukui.rc` 已经跑到 `early-init`，`mount_all` 也用了新 fstab：`/data` 的两条记录是 `rec[7]` 和 `rec[8]`。两条都是 invalid magic，日志停在这里。

`fs_mgr` 只在 `partition_wiped()` 为真时格式化。那个函数要求分区开头 4096 字节全是 0 或全是 0xFF。metadata 和 userdata 都落在原来的 postmarketOS 根文件系统里，开头是旧 ext4 的残留，所以被当成已有数据，没有格式化。`/data` 仍然不存在，keystore 的崩溃路径还在。

只把这两个分区的开头 1 MiB 写成 0，读回的前 4096 字节都是全 0。super、内核槽、日志分区没动。

第六次 Ctrl+U 没有回到选盘界面，停在服务循环上。U 盘上的 `kukui-phase3.log` 只有 76678 字节，sha256 `6591c09e652ae021faeb3eb8e095b8f7854515f5e88c1919cdb3072fa6630e7b`，最后一行停在内核时间 6.738 秒：`early_system_aconfigd_platform_init` 还在 waiting。没有 `kukui-phase3-logcat.txt`。屏幕上 35 秒到 50 秒仍在刷同一句：`servicemanager` 说调用者是 vold（pid 3096，`u:r:vold:s0`），`android.system.keystore2.IKeystoreService/default` 找不到，于是每秒再试一次把它当成 lazy AIDL 服务拉起来。这和 Gru 阶段 3 里「停在服务循环、不回选盘菜单」是同一类，不是同一个故障。Gru 先把 userdata 格式化成 f2fs 再写入，第一次启动没有走进 `encryptFstab`；他们的循环是 netd 缺 `xfrm_user`，以及后来的 USB HAL、ashmem、ION。这里是 vold 在 `mount_all` 里等 keystore2。keystore2 属于 `early_hal`，init 要等 `mount_all` 返回才启动它，所以它永远不会出现。没有崩溃，`critical` 的重启也不会发生。照片里 `mtk-power-controller` 对 `11230000.mmc` 和 `11220000.mmc` 的 `sync_state pending` 是 eMMC 的延迟探测，不是这个循环。

日志提前截断是因为 `kukui-keep` 的读线程每写一块就对同一根 U 盘 `fsync`。控制台走的是 tty0，不经过这个写线程。下一次 `fsync` 被卡住之后，128 KiB 的 printk 环不再被读走；断电时，最后一次成功 `fsync` 之后的内容都没落盘。`on fs` 再去挂 `pmOS_boot` 也会得到 EBUSY，因为写线程还占着这个文件系统，所以 logcat 文件根本不会出现。

这次把 userdata 的 `fileencryption` 和 `keydirectory` 拿掉。`mount_all` 用 `make_f2fs` / `mke2fs` 自己格式化，不再调用 `vdc cryptfs encryptFstab`。keystore2 改到 `/data` 已经挂上之后再启动。文件加密留到能进主界面之后再加，现在加回去会再次死锁。`kukui-keep` 改成一个进程只读 kmsg、写进 1 MiB 管道，另一个进程负责写盘和 `fsync`。慢的 `fsync` 不再停掉读环。`init.kukui.rc` 不再第二次挂载日志分区。

新 FIT 12,337,152 字节，读回 `sdb1` 的 sha256：

```text
73481569882e62fe4d495fae1b0e48b36f29f9cdc721d5b33302bd9a3b21b1a5
```

命令行没变。新的 `super.raw` 仍是 8,589,934,592 字节，读回 `sdb3` 的 sha256：

```text
ddfb3facc317d0b79aaeecc490e74adcf064da6d1eeb880b0dd157ba3f3348f6
```

metadata 和 userdata 的开头仍是全 0。这次启动会格式化 metadata（16 MiB）和 userdata（约 50 GiB）。`make_f2fs` 不把整块盘写满，但第一次格式化仍可能要几分钟。屏幕在这段时间里可以一直很安静。写入时平板不在网上，eMMC 没有重新核对。

第七次 Ctrl+U 大约半分钟回到选盘界面。日志 119403 字节，1276 行，sha256 `783e120b3cbaba410d0de0236e5e88ea5fe96ce6588f4b03132c44beba7c6e5d`，写到内核时间 29.5 秒。`make_f2fs` 把 `/dev/block/sda6` 格式化成 f2fs，`fsck.f2fs` 用了 5825 毫秒，内核打印 `F2FS-fs (sda6): Mounted with checkpoint version`。紧接着是 `SELinux: (dev sda6, type f2fs) has no security xattr handler`。这颗内核的 `CONFIG_F2FS_FS_XATTR=y`，但 `CONFIG_F2FS_FS_SECURITY` 没开，`security.*` 扩展属性返回 `EOPNOTSUPP`。SELinux 因此拒绝这次挂载，`/data` 仍是根上的 erofs。之后 `mkdir /data/...` 全部是 `Read-only file system`。`vdc cryptfs init_user0` 退出状态 25，日志写的是 `Failure (reboot suppressed): init_user0_failed`。文件加密已经关掉，这条路径本身不重启。keystore2 随后被 `crash_dump64` 跟踪，init 杀掉它。它是 `critical`，连续崩溃会回到选盘界面。日志停在第一次杀掉之后。

只重编了内核，打开 `CONFIG_F2FS_FS_SECURITY`。版本仍是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2`，ramdisk 里的模块不用换。super 没动。userdata 上的 f2fs 保留，下一次直接挂，不再格式化。新 FIT 12,333,056 字节，读回 `sdb1` 的 sha256：

```text
ddfb37674f384398a94f844344a3a1ab5bd85cd9f28214baa2efc18cb18e58fe
```

命令行没变。写入时平板不在网上，eMMC 没有重新核对。

第八次 Ctrl+U 大约一分钟回到选盘界面。日志 125764 字节，1368 行，sha256 `9baeb32dfe95a2e9ae08d6f73b16dc2db55f5e1cec5e7ea3214ecb7916afe6df`，写到内核时间 61.67 秒。`/data` 直接挂上，检查点 `2d27437e`，没有再格式化。`on post-fs` 在 sda6 上建了 `/data/misc/keystore`。keystore2（pid 3228）一直活到关机时收到 SIGTERM。配额有一行 `Failed to enable quota tracking (type=0, err=-3)`，挂载仍然成功。`/cache` 的 chown 是 erofs，这块盘没有 cache 分区，启动继续往下走。

压缩 APEX 解压花了大约 46 秒。随后内核打印 `verity: unknown target type`，`DM_TABLE_LOAD` 失败。`CONFIG_DM_VERITY` 当时是 `=m`，模块没有加载，device-mapper 不认识这个目标。tethering 是 `com.android.tethering.capex`，没能挂上。`/system/etc/init/netbpfload.rc` 里的 `bpfloader` 在 APEX 没覆盖它的时候是 `/system/bin/false`，并且 `reboot_on_failure reboot,netbpfload-missing`。这个服务在 61.295 秒启动，22 毫秒后 init 写 `Reboot start, reason: reboot,netbpfload-missing`。`apexd` 先 `Activated 19 packages`，再 `Activated 0 packages`。`/cache` 只读、没有 boot HAL、`verity_update_state` 失败、`prng_seeder` 和 `1100bc00.svs` 的延迟探测都不是这次重启的原因。

只重编了内核，把 `CONFIG_DM_VERITY` 从 `=m` 改成 `=y`。`CONFIG_DM_BUFIO` 和 `CONFIG_CRYPTO_SHA256` 跟着是 `=y`。版本仍是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2`，ramdisk 里的模块不用换。super 没动。userdata 上的 f2fs 保留。新 FIT 12,349,440 字节，读回 `sdb1` 的 sha256：

```text
32b31b3ff0183b22228d3db716725305a457b04553628d9bdf9497cbcf86d067
```

命令行没变。写入时平板不在网上（`10.0.0.117` 连接超时），eMMC 没有重新核对。

第九次 Ctrl+U 没有回到选盘界面。日志 272320 字节，2476 行，sha256 `992f31c78a5ecc72a43773da21dae465b9f53e39262b9848afdc177824b3e448`，写到内核时间约 149 秒，人把电源按掉了。`NetBpfLoad: success`，压缩 APEX 的 verity 挂上了。屏幕几秒亮一次再灭：`surfaceflinger` 反复 `SIGABRT`，`bootanim` 被拉起后又被 zygote 的 onrestart 杀掉。`/data/tombstones` 是空的，abort 正文只进了 logd。对应的代码是 `Initial display configuration failed: HWC did not hotplug`。`drm_hwcomposer` 拿不到 DRM master 时建一个 null display，而且不给这个 null display 发 hotplug。内核在 1.3 秒创建了 `mediatekdrmfb`，13.6 秒解开 vtcon 只换成 dummy 控制台，master 还在内核客户端上。minigbm 也会先打开没有 render node 的 `card0`。`vendor.audio-hal` 不存在、`/sys/power/state` 的 EINVAL、`cgroup.kill` 缺失，都是这个循环的连带，不是起因。配额仍是 `err=-3`，挂载成功。

这次重编了内核：`DRM_IOCTL_SET_MASTER` 可以从已经占着 master 的打开者手里接手。版本仍是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2`。命令行加上 `drm_client_lib.active=none`，内核不再建立 fbdev 客户端。super 没动。userdata 上的 f2fs 保留。新 FIT 仍是 12,349,440 字节，读回 `sdb1` 的 sha256：

```text
1ce4aba305610ea7314dae95e8793fb74fffcbf98598b2c98dfed0631cc669b5
```

写入时平板不在网上，eMMC 没有重新核对。

第十次 Ctrl+U 屏幕全黑，背光几秒闪一次。人在大约 58 秒强制关机，没有回到选盘界面。日志 190169 字节，1832 行，sha256 `7c96e5e5a168c98d4bc2bf0fcda4962c27aed95a6452ac8677cc9bb0447213b5`，写到内核时间 58.08 秒。`drm_client_lib.active=none` 生效：内核打印 `Unknown DRM client none`，没有 `fb0`。`surfaceflinger`（pid 3904、4338）都执行到了 `ctl.start bootanim`，hotplug 已经过了，不是 “HWC did not hotplug”。大约 160 毫秒后 RenderEngine 线程退出，`surfaceflinger` 收到 SIGABRT。`bootanim` 活大约 5 秒后被杀掉。21.7 秒时 light HAL 读了 `backlight_lcd0`。没有 fbcon，合成器在送出画面之前崩溃，所以全黑，背光跟着这次上电和 bootanim 闪。

abort 正文仍然不在这份 kmsg 里。`/data/tombstones` 是空目录，`/data/misc/logd` 只有 0 字节的 `event-log-tags`。`pmOS_boot` 当时是没有日志的 ext2。这次挂载内核就报 `freeing already freed block`，块位图是坏的。写日志的 fsync 一卡住，读 kmsg 的进程就停，printk 环把 abort 盖掉。强制断电又会把这个没有日志的文件系统再弄坏一次。

日志先改成强制断电之后还能留下 abort。`e2fsck` 修好了 `sdb2`，`tune2fs -j` 给它加了日志，GPT 没动。`kukui-keep` 开写新日志之前把上一份改名为 `kukui-phase3.log.prev`，管道扩到 4 MiB。`kukui-logcat` 在 post-fs-data 启动，把 `SurfaceFlinger`、`drmhwc`、`RenderEngine`、`DEBUG` 这些过滤后的 logcat 逐行以 `KUKUI_LOG` 写进 `/dev/kmsg`，由已经开着的那份日志 fsync。同一份流还转到 `/data/kukui-logcat.txt`。不再第二次挂载 `pmOS_boot`。

画面这边，第十次崩溃发生在初始化完成之后的 RenderEngine 线程上，那段时间它在做 shader cache。`service.sf.prime_shader_cache` 设成 false，第一帧走 bootanim 真正要画的路径。如果崩溃在别的地方，背光仍可能闪，但 abort 正文会在 `KUKUI_LOG` 里。内核没有重编，命令行没变。新 FIT 12,349,440 字节，读回 `sdb1` 的 sha256：

```text
62a6a287d9fa078133914dd4666d8fddc3e00764b7698e96064f39f25b4a1805
```

新的 `super.raw` 仍是 8,589,934,592 字节，读回 `sdb3` 的 sha256：

```text
9a09c7d10c5dd068f62d32d287983f61eddd65ad0880ed0874002fd3ce672c3d
```

写入时平板不在网上，eMMC 没有重新核对。userdata 上的 f2fs 保留。

第十一次 Ctrl+U 背光从全黑变成常亮，屏幕上没有画面。人在大约 373 秒强制关机，没有回到选盘界面。日志 1,386,553 字节，10570 行，sha256 `7c1cf1b10c3cb576d9152ab0c514ef6f11dcaf03f6537ccc26e7ae30dec364f4`，写到内核时间 373.78 秒。上一份日志留在 `kukui-phase3.log.prev`。`KUKUI_LOG` 在。`drm_client_lib.active=none` 仍在。`surfaceflinger`（pid 3841）只启动一次，RenderEngine 打印了 `GL_MAX_TEXTURE_SIZE = 16384`，`drmhwc` 挂上 `DSI-1`，模式是 60 Hz。背光常亮是因为合成器把面板电源打开之后自己没有退出。没有像素是因为 `bootanim`（pid 4051）从 63 秒到关机一直报 `eglMakeCurrentImpl error 300b (EGL_BAD_NATIVE_WINDOW)`。

minigbm 先打开 render 节点。这颗机器上那是 Panfrost 的 `renderD128`。`DRM_IOCTL_MODE_CREATE_DUMB` 不允许 render 客户端，Panfrost 也没有 `dumb_create`。分配失败以后 Mesa 把窗口标成 Lost，开机动画每一帧都在这个已经坏掉的窗口上 `eglMakeCurrent`。`vendor.minigbm.device=/dev/dri/card0` 让 gralloc 改到 Mediatek 的主节点上分配，那边的 dumb ioctl 能用。`service.sf.prime_shader_cache=false` 留着，这次不是它导致的。

`netd` 以状态 1 退出，init 按 onrestart 杀掉 zygote，然后两边互相重启，一直到关机。状态 1 只来自 `BandwidthController::enableBandwidthControl()`：静态规则用了 `-m bpf` 和 `-m policy`，内核里这两项原来没编。`iptables-restore` 读 `/proc/sys/kernel/modprobe` 也说明匹配模块没有预先加载。内核映像没重链，版本仍是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2`。新的匹配和 iptables 表做成模块，放进 ramdisk，在 `netd` 之前由 `modules.load` 加载。`Zygote:W` 不再镜像进 kmsg，避免预加载警告把同一条错误刷满。kmsg 里同一条 logcat 只留第一次。

命令行没有改。新 FIT 12,414,976 字节，读回 `sdb1` 的 sha256：

```text
30c6208789ba6a5f44206799d20c6220ed5b7e17e7d0bb0249cae2da5c521a7b
```

新的 `super.raw` 仍是 8,589,934,592 字节，读回 `sdb3` 的 sha256：

```text
db535a34ba7d34dac9ff75bc0d81af2c80412e612e537b8ccc776b0589f74c35
```

写入时平板不在网上，eMMC 没有重新核对。userdata 上的 f2fs 保留。

第十二次 Ctrl+U 开机动画流畅，然后停在动画上。人在大约 508 秒强制关机，没有回到选盘界面。日志 1,320,539 字节，9734 行，sha256 `df63561e8c46b397a7e90304113d42580911fff3631388570e33d7814d5722c4`，写到内核时间 508.34 秒。上一份日志留在 `kukui-phase3.log.prev`。`eglMakeCurrent` 的 `300b` 没有再出现。`netd` 没有再以状态 1 退出。`BootAnimation` 和 `surfaceflinger` 都在。

停住是因为 `system_server` 的 `batterystats-handler` 反复崩溃：`synchronizeKernelRCU failed: Unknown error -97`。网络统计要 `socket(AF_KEY, SOCK_RAW, PF_KEY_V2)` 再立刻关掉，关闭时内核在 `pfkey_release()` 里调用 `synchronize_rcu()`。`CONFIG_NET_KEY` 原来没编，`socket()` 返回 `EAFNOSUPPORT`（97）。`system_server` 反复退出，开机动画就等不到启动完成。同一份日志里 systemui 和 networkstack 的 `DeadSystemException` 是这个崩溃的连带。

`netd` 每次启动还报 `Unable to create netlink socket for family 5`（`NETLINK_NFLOG`）和 `Failed NFULNL_CFG_CMD_PF_UNBIND: Invalid argument`。`CONFIG_NETFILTER_NETLINK_LOG` 原来没编。这条不让 `netd` 退出。另外有 `cannot find interface dummy0`：`CONFIG_DUMMY` 已经是模块，但没有放进 `modules.load`。`RouteController::Init` 允许 dummy 网络失败，所以这也不是动画停住的原因。

内核映像没重链。版本仍是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2`，映像时间仍是 2026-10-31 01:18。`CONFIG_NET_KEY=m` 和 `CONFIG_NETFILTER_NETLINK_LOG=m` 做成 `af_key.ko`、`nfnetlink_log.ko`，加上已经编好的 `dummy.ko`，放进 ramdisk，由 `modules.load` 加载。`af_key` 依赖已经在列表里的 `xfrm_algo`，`nfnetlink_log` 依赖已经在列表里的 `nfnetlink`。super 没动。userdata 上的 f2fs 保留。

命令行没改。新 FIT 12,447,744 字节，读回 `sdb1` 的 sha256：

```text
aa50a78be66cdf1b75dd8cef3b7666eeec577418e89ea009e74b4596d1910bb2
```

写入时平板不在网上，eMMC 没有重新核对。

第十三次 Ctrl+U 开机动画流畅，大约 56 秒后动画自己退出，然后机器在内核时间 78 秒自己重启。日志 241796 字节，2233 行，sha256 `a76a57a60936a3b486a3cd4d253a01df85cc521569cfe78ef0402155a921db5b`，写到 78.70 秒的关机流程。上一份日志留在 `kukui-phase3.log.prev`。`synchronizeKernelRCU` 的 -97 没有再出现。`dummy0` 也没有再报找不到。`af_key.ko`、`nfnetlink_log.ko`、`dummy.ko` 都在 5.3 秒加载成功。

重启是 Rescue Party 的恢复出厂。`system_server` 的 ActivityManager 线程两次 abort：`Kernel configs could not be fetched`。`Debug.isVmapStack()` 要读 `/proc/config.gz`，`CONFIG_IKCONFIG=m` 的 `configs.ko` 没有放进 `modules.load`，文件不存在，`CHECK` 在 userdebug 上直接把进程打死。zygote 跟着重启。第二次起来的 `system_server` 调用了 `RecoverySystem.rebootPromptAndWipeUserData`，misc 上的 BCB 写成 `boot-recovery` 和 `--prompt_and_wipe_data`，原因是 `RescueParty,null`。这台机器的 USB 口在 host 模式，`/sys/class/android_usb/android0/state` 不存在，userdebug 本来靠这点关掉 Rescue Party，所以它开着。第十二次启动里 `system_server` 已经崩溃过很多轮，这一次再崩就升到恢复出厂。

动画退出之后，启动器和 SystemUI 的 RenderThread abort：`Failed to create context, error = EGL_NOT_INITIALIZED`。`ueventd.kukui.rc` 把 `/dev/dri/*` 设成 `0660 system graphics`。开机动画和 surfaceflinger 在 graphics 组里，能打开节点。普通应用不在这个组里，打不开 render 节点。蓝牙也在崩溃：`initializationComplete` 的状态不是成功，HAL 接着在 `FD_SET` 里用了 -1。这两处不是这次自己重启的原因。`netd` 仍然打不开 netlink family 5，`nfnetlink_log` 注册的不是 `NETLINK_NFLOG`，这条不让 `netd` 退出。

`configs.ko` 放进 ramdisk。`/dev/dri/*` 改成和通用 `ueventd.rc` 一样的 `0666 root graphics`。`persist.sys.disable_rescue=true`，避免还没做完的蓝牙崩溃再把 userdata 恢复出厂。misc 上的 wipe 命令已经清掉。内核映像没重链，版本仍是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2`。userdata 上的 f2fs 保留。

新 FIT 12,505,088 字节，读回 `sdb1` 的 sha256：

```text
9734b6d416026f1fb0d12e15c7566a0ddd9b7e028ea4c1acebfde0bf5fa6d86e
```

新的 `super.raw` 仍是 8,589,934,592 字节，读回 `sdb3` 的 sha256：

```text
5a65b6185ce633d5c3e5065726323a9dcc6f2036db7cff524aa33315a7dfe6e6
```

写入时平板不在网上，eMMC 没有重新核对。

第十四次 Ctrl+U 进入桌面。zygote 在内核时间 24.06 秒启动。开机动画在 28.85 秒起来。SurfaceFlinger 报 Mali-G72 (Panfrost)、OpenGL ES 3.1 Mesa 25.3.3。`sys.boot_completed=1` 在 55.48 秒。`configs.ko` 在 5.65 秒加载。没有再出现 `Kernel configs could not be fetched`，也没有 Rescue Party 重启。日志 231064 字节，2189 行，sha256 `9276aba962ac00e6be95a5f113f149eb5f6ffc36a301f65273bb440c983797d9`，写到 122.00 秒。

这次停在灭屏之后的挂起失败上。117.08 秒 SurfaceFlinger 把显示设成 power mode 0，用户空间冻结被拒绝（先是 300 个任务，再是 308 个），任务随后恢复。不是崩溃重启。触摸、键盘盖和外接鼠标在内核里都已经注册，Android 没有收到事件。`/dev/input` 在 17.05 秒还不存在。原因和下一阶段的开头写在 [阶段 4](phase-4.md)。

2026-10-31 回到内置盘之后核对过：postmarketOS v26.06，根在 `/dev/mmcblk0p3`，`uname -r` 是 `6.18.28-mt81`，`/boot/vmlinuz.kpart` 的 sha256 仍是 `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e`。

`lunch` 是 `lineage_kukui-trunk_staging-userdebug`。Mesa 的 gallium 只有 panfrost，Vulkan 驱动是空的。`mapper.minigbm_upstream.so` 在 vendor 里。源码树里 Gru 留下的 `stylusctld` 文件上下文缺测试行，补了一行 `system/sepolicy/contexts/file_contexts_test_data`，否则 sepolicy 检查过不了。这不是 Kukui 的功能。

## 完成

第十四次 Ctrl+U 三条都达到。

1. 面板上进入了桌面。
2. 日志里 zygote 在 24.06 秒启动，surfaceflinger 用 Panfrost 在合成，`sys.boot_completed=1` 在 55.48 秒。
3. 回到内置盘仍是 v26.06，eMMC 上 `/boot/vmlinuz.kpart` 的 sha256 仍是 `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e`。

有线 adb 不是通过条件：这个 Type-C 口在 U 盘模式下是 host。触摸、键盘和鼠标不能用，那是阶段 4 的第一件事，见 [阶段 4](phase-4.md)。
