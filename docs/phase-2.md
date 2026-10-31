# 阶段 2：Android 内核配置

2026-10-30 结束。路线图在 [roadmap.md](roadmap.md)。Ctrl+U 启动了 `6.18.28-mt81-kukui2`，日志写在 U 盘 `pmOS_boot` 的 `/kukui-phase2.log`。没有挂 postmarketOS 的根，没有写 eMMC，没有测休眠。副本是 [bringup/phase2/kukui-phase2.log](../bringup/phase2/kukui-phase2.log)，589 行，sha256 `7d01382146d7dfd510af598ce34934ffd1a1b77b4e68e089aaf9f3eefbef13f5`。

## 源码

发行版包是 `linux-postmarketos-mediatek-mt81` 6.18.28-r0，和 v26.06 分支上的 APKBUILD 一致：`pkgver=6.18.28`，`pkgrel=0`。源码包 `linux-6.18.28.tar.xz` 的 sha512 与那份 APKBUILD 相同。补丁按打包顺序打上：蓝牙、mt8186 DPI、HDMI codec、HDMI widget、IT6505 音频、mt8186 FE、pmdomain。这些补丁不改 Krane 的 DTB。FIT 里的 DTB 仍是平板 `/boot/mt8183-kukui-krane-sku176.dtb`，没有重新编译设备树。

基线配置是这台机器 `/boot/config`，不是更新的 pmaports 树。它和 v26.06 的打包配置只差编译器探测出来的 `CONFIG_CC_CAN_LINK`。

工作站上能用来编 CFI 的是 Ubuntu clang 21.1.8 和 LLD 21.1.8。发行版内核是 Alpine clang 22.1.3。没有为了凑编译器关掉 `CONFIG_CFI` 或 `CONFIG_SHADOW_CALL_STACK`。构建命令是 `ARCH=arm64 LLVM=-21`，`KBUILD_BUILD_VERSION=1-kukui-phase2`。

## 打开的选项

下面每一项都先在 `linux-6.18.28` 的 Kconfig 里确认过符号存在，再写进配置。片段在 `bringup/phase2/config.fragment`。

| 选项 | 原来 | 现在 |
| --- | --- | --- |
| `CONFIG_LOCALVERSION` | `-mt81` | `-mt81-kukui2` |
| `CONFIG_EROFS_FS` | `=m` | `=y` |
| `CONFIG_SECURITY_NETWORK` | 未设置 | `=y` |
| `CONFIG_SECURITY_SELINUX` | 配置里没有 | `=y`。它依赖 `SECURITY_NETWORK`、`AUDIT`、`NET`、`INET`，后三项原来就是 `=y` |
| `CONFIG_ANDROID_BINDERFS` | 未设置 | `=y`。`CONFIG_ANDROID_BINDER_IPC` 原来就是 `=y` |
| `CONFIG_CPUSETS_V1` | 未设置 | `=y`。`CONFIG_CPUSETS` 原来就是 `=y` |
| `CONFIG_FS_ENCRYPTION` | 未设置 | `=y` |
| `CONFIG_F2FS_FS_SECURITY` | 未设置 | `=y`。阶段 3 补上，否则 SELinux 拒绝挂载 f2fs |
| `CONFIG_DM_VERITY` | `=m` | `=y`。阶段 3 补上，否则压缩 APEX 找不到 verity 目标 |

`olddefconfig` 跟着带上的是这些选项自己的默认值和 `select`，不是另加的功能：

- `CONFIG_EROFS_FS_XATTR`、`CONFIG_EROFS_FS_SECURITY`、`CONFIG_EROFS_FS_ZIP` 以及 lzma、deflate、zstd 原来就是 `=y`，编在 erofs 模块里。父选项改成 `=y` 之后，它们进内核，不再有 `erofs.ko`。
- `CONFIG_SECURITY_SELINUX` 选中 `CONFIG_NETWORK_SECMARK`。`CONFIG_SECURITY_NETWORK_XFRM` 保持关闭。
- `CONFIG_SECURITY_SELINUX_DEVELOP=y` 是 Kconfig 的默认。SELinux 一旦被启用，内核以 permissive 启动，除非命令行写 `enforcing=1`。`CONFIG_SECURITY_SELINUX_BOOTPARAM` 没开。
- `CONFIG_FS_ENCRYPTION_ALGS=y`，`CONFIG_PROC_PID_CPUSET=y`，`CONFIG_LSM_MMAP_MIN_ADDR=32768`。

`CONFIG_LSM` 仍是 `landlock,lockdown,yama,loadpin,safesetid,integrity,bpf`，没有把 selinux 加进去。这一段的命令行也不写 `security=selinux`。所以 Ctrl+U 时 SELinux 编进内核但不会初始化。6.18 的 `security/security.c` 里，`security=` 会把命令行点名的 legacy major LSM 追加进启用列表。阶段 3 再写 `security=selinux` 就会用上它。

保持原样的有：`CONFIG_SECURITYFS=y`，`CONFIG_CFI=y`，`CONFIG_SHADOW_CALL_STACK=y`，`CONFIG_NF_TABLES=m`，`CONFIG_USB_CONFIGFS=m`，`CONFIG_USB_CONFIGFS_F_FS=y`，ext4、f2fs、device-mapper、dm-crypt、Panfrost、zram。没有把原来 `=y` 的项关掉，也没有把 netfilter 编进内核。

`uname -r` 会是 `6.18.28-mt81-kukui2`。发行版内核仍是 `6.18.28-mt81`。

## init

脚本在 `bringup/phase2/init`。磁盘规则和阶段 1 相同：`insmod usb-storage`，只挂 `sd*` 上 `PARTNAME=pmOS_boot` 的分区。日志写到 `/kukui-phase2.log`，不覆盖阶段 1 的文件。

日志里有：

- `/proc/version`，用来看本地版本
- `/proc/filesystems`，erofs 编进内核时不用加载模块就会出现
- 挂 `binder` 文件系统的结果
- 用 cgroup v1 挂 cpuset 的结果
- `insmod configs.ko` 之后，`/proc/config.gz` 里上面那些选项的行
- `dmesg`，最后一行 `=== end ===`

`usb-storage.ko` 和 `configs.ko` 放在 initramfs 里，vermagic 是 `6.18.28-mt81-kukui2`。不能用发行版那份模块。

## 模块

`modules_install` 的结果在 U 盘 `pmOS_boot` 的 `/kukui/modules`，21 MiB，里面有 `modules.dep`。这不是 eMMC 的 `/lib/modules`，也不是 U 盘根文件系统的 `/lib/modules`。eMMC 上的 `/boot/vmlinuz.kpart` 没有动。

## 镜像

在平板上用开发者密钥签名。命令行核对过：

```text
kern_guid=%U console=tty0 loglevel=7 deferred_probe_timeout=30
```

没有 `root=`。内核 lzma 后 9,775,743 字节。initramfs 1,876,992 字节，sha256 `b381d14b8cd8851114ecc9d52789a6ef2fcb5ab545bbbee6531659f1634e87e0`。`depthchargectl check` 退出码 0。镜像 11,796,480 字节，小于 32 MiB。sha256：

```text
846994f18fb1acfc197bda72fb02a8db0defb09f81dcc0e850160730eeaca1e0
```

写入脚本是 `bringup/phase2/write-usb-kernel.sh`，只写工作站上的 `/dev/sdb1`。2026-10-30 读回 11,796,480 字节，sha256 仍是 `846994f18fb1acfc197bda72fb02a8db0defb09f81dcc0e850160730eeaca1e0`。写入之后平板仍是同一次启动，`boot_id` 是 `580f3546-f460-45a8-8651-b1001047554a`，根仍是 `/dev/mmcblk0p3`，`/boot/vmlinuz.kpart` 的 sha256 仍是 `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e`。

阶段 1 那份 FIT 还在 `work/phase1/kernel.kpart`，原来的 postmarketOS FIT 在 `work/phase1/pmos-vmlinuz.kpart`。

## 人工测试

U 盘已从工作站卸载。

1. 卸下 U 盘，插到 Krane 上。
2. 重启，开发者屏幕按 Ctrl+U。面板可以是黑的。
3. 等大约一分钟。init 写完日志后停住。
4. 再重启，不要按 Ctrl+U。应回到 eMMC 上的 postmarketOS v26.06，Plasma 仍在。
5. 把 U 盘插回工作站，读 `pmOS_boot` 上的 `kukui-phase2.log`。不要按 UUID 或卷标在平板上挂这份分区。

完成标准：

1. 日志第一行是 `kukui-android phase2`，`uname` 里有 `6.18.28-mt81-kukui2`。`/proc/filesystems` 有 erofs，binderfs 和 cpuset v1 挂载成功，`/proc/config.gz` 里 `CONFIG_SECURITY_SELINUX=y`、`CONFIG_EROFS_FS=y`、`CONFIG_ANDROID_BINDERFS=y`、`CONFIG_CPUSETS_V1=y`。末尾是 `=== end ===`。
2. 不按 Ctrl+U 时，eMMC 上仍是 v26.06。
3. eMMC 内核分区没有被这次写入碰到。

这一段不测休眠。

## 结果

Ctrl+U 写出的日志第一行是 `kukui-android phase2`，最后一行是 `=== end ===`。`uname` 是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2`，编译器是 Ubuntu clang 21.1.8。命令行没有 `root=`，也没有 `security=selinux`。挂的是 `/dev/sda2`。`/proc/filesystems` 里有 erofs。binderfs 挂上之后能看见 `binder`、`hwbinder`、`vndbinder`。cgroup v1 的 cpuset 挂上了，目录里有 `cpuset.cpus`。`/proc/config.gz` 里 `CONFIG_SECURITY_SELINUX=y`、`CONFIG_SECURITY_NETWORK=y`、`CONFIG_EROFS_FS=y`、`CONFIG_ANDROID_BINDERFS=y`、`CONFIG_CPUSETS_V1=y`、`CONFIG_FS_ENCRYPTION=y`，`CONFIG_CFI` 和 `CONFIG_SHADOW_CALL_STACK` 仍是 `=y`，`CONFIG_NF_TABLES` 仍是 `=m`。`CONFIG_LSM` 里没有 selinux。没有 panic。阶段 3 后来又把 `CONFIG_F2FS_FS_SECURITY` 和 `CONFIG_DM_VERITY` 编进内核，版本字符串没变，原因记在 [阶段 3](phase-3.md)。

ext2 挂载时有一行 `mounting unchecked fs, running e2fsck is recommended`。前一次 Ctrl+U 停在睡眠里，分区没有干净卸载。日志还是写进去了。

不按 Ctrl+U 的下一次启动：`boot_id` 是 `7ed1eb4a-7f21-4ab7-84e1-bb227cce9775`，根是 `/dev/mmcblk0p3`，内核 `6.18.28-mt81`，发行版 postmarketOS v26.06，`plasmashell` 和 `kwin_wayland` 在跑。`/boot/vmlinuz.kpart` 的 sha256 仍是 `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e`。
