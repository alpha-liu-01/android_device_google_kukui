# 打包和更新

2026-11-02。路线图的阶段 6 和后面的 OTA 都从这里展开。打包脚本在 `bringup/release/`。同一天用 `flash-usb.sh` 写过一块 58 GiB 的 USB SD/MMC（`/dev/sdb`，序列号 `20120501030900000`）。第一次 Ctrl+U 进了桌面，第一次开机没有 Wi-Fi，第二次才有。随后用带重试的内核把这张盘整盘重写，userdata 是空的。再一次 Ctrl+U 是刷写后的第一次开机，Wi-Fi 从第一次探测起来了；重试子进程没有进入 Android 的根。随后用会从 `/proc/1/root` 进入系统根的内核把这张盘又整盘抹掉重写。这次 Ctrl+U 的 Wi-Fi 仍是第一次探测连上的；子进程在 `switch_root` 之前就进了根，脚本没有执行。随后用等 `/proc/1/exe` 变成 `/system/bin/init` 才进根的内核又整盘抹掉重写。这次第一次开机没有 Wi-Fi，第二次才有。第一次开机的日志里 ath10k 在 97 秒探测失败，脚本没跑。只认 `second_stage` 仍看不到另一个挂载命名空间里的 `/vendor`。随后把先 `setns` 进 init 挂载命名空间的内核整盘抹掉重写。这次 Ctrl+U 的第一次开机有 Wi-Fi，但是第一次探测自己完成的；`sh` 在 runtime APEX 挂上之前就退出了，脚本没有跑。随后把会重试 `exec` 的内核整盘抹掉重写。这次 Ctrl+U 是第一次开机：向导里没有 Wi-Fi，第一次探测超时之后脚本重载了 ath10k，进桌面时已经连上。细节在 [emmc.md](emmc.md)。

## 建议

先做两样可以分开交付的东西。

1. 工作站上的一条打包流程，产出一个 zip。zip 里是 U 盘各分区的镜像和一个写盘脚本。用户在电脑上解压、指定 U 盘，脚本写成一张能 Ctrl+U 的安装盘。这张盘不写 eMMC。
2. 安装器里加「更新系统」。机器从这张 U 盘启动，确认目标是 `11230000.mmc` 之后，只换 eMMC 上的 `super` 和 Android 内核槽。`userdata`、`metadata`、Linux 根分区和分区表都不动。

在 eMMC 上已经启动的 Android 里直接换自己的 `super`，留到这两步都稳定之后。depthcharge 没有 recovery 键，Type-C 也不能同时当启动盘和 sideload 口。恢复模式可以以后做成菜单里的第三项，用现在这条「从 U 盘写 eMMC」的路径就够做第一次可分发的更新。

`bringup/phase3/write-usb.sh`、`bringup/phase4/write-sandisk.sh`、`write-super-cam.sh`、`write-install-payload.sh` 继续只作为当时那张盘的记录。发布脚本不读取它们，也不继承写死的序列号、校验和和分区号。

## 现在的两套盘

U 盘是安装盘，也是写坏之后的退路。eMMC 是已经装好的双系统。两套 GPT 的角色不一样，不能把 U 盘整盘复制到 eMMC。

U 盘，扇区 512 字节：

| 分区 | 起始扇区 | 名称 | 内容 |
| --- | --- | --- | --- |
| 1 | 8192，长 65536 | `pmOS_kernel` | USB 用的 Android FIT。`androidboot.boot_devices=soc/11201000.usb/11200000.usb`。priority 15、tries 15、successful 1 |
| 2 | 73728 | `pmOS_boot` | ext4。`/kukui-install/` 放 eMMC 用的 `android.kpart`、`menu.kpart` |
| 3 | 1122304，长 16777216 | `super` | 8 GiB 原始镜像。动态分区在里面 |
| 4 | | `metadata` | ext4，安装时格式化成空的 |
| 5 | | `misc` | 4 MiB，空 |
| 6 | 到盘尾 | `userdata` | f2fs，安装时格式化成空的 |

eMMC 上现在的双系统：

| 分区 | 名称 | 更新时 |
| --- | --- | --- |
| mmcblk0p1 | `pmOS_kernel` | 不动 |
| mmcblk0p2 | `pmOS_boot` | 不动 |
| mmcblk0p3 | `pmOS_root` | 不动 |
| mmcblk0p4 | `menu_kernel` | 只有菜单 FIT 变了才换内容，不改 GPT 属性 |
| mmcblk0p5 | `android_kernel` | 换内容，不改 GPT 属性 |
| mmcblk0p6 | `bootmenu` | 不动 |
| mmcblk0p7 | `super` | 整段换掉 |
| mmcblk0p8 | `metadata` | 不动。锁屏和文件加密的密钥在这里 |
| mmcblk0p9 | `misc` | 不动 |
| mmcblk0p10 | `userdata` | 不动 |

Android 内核槽的命令行是 `androidboot.boot_devices=soc/11230000.mmc`。U 盘内核槽保持 USB 那条。两份 FIT 的内核 lzma 和 `mt8183-kukui-krane-sku176.dtb` 来自同一次内核构建，差别只在命令行和 ramdisk 里给 eMMC 启动用的文件。

`super` 里的模块必须和这份内核是同一次构建。清单把 `kernel.kpart`、`android.kpart`、`menu.kpart` 和 `super.img` 的 sha256 写在一起。对不上就拒绝写入。

## 1. 构建和 USB zip

### 工作站上产出什么

一次发布得到四个镜像：

- `kernel.kpart`：U 盘自己启动用的 FIT。
- `android.kpart`：装到 eMMC `android_kernel` 的 FIT。
- `menu.kpart`：装到 eMMC `menu_kernel` 的 FIT。
- `super.img`：逻辑大小正好 8589934592 字节。Android 构建经常给出 sparse 文件，打包前用 `simg2img` 展开，展开后的长度必须是这个数。

内核不是 `lunch` 编出来的。源码是已经在这台机器上验证过的 6.18.28-mt81，加上 `bringup/phase2/config.fragment`、`bringup/camera/` 和 `bringup/kernel/` 里的补丁。FIT 用 `futility vbutil_kernel` 和开发者密钥打包，板名 `mt8183`，压缩 lzma，只放 sku176 这一块 DTB。打包步骤以 `bringup/phase4/pack-install-fits.sh` 为底，发布脚本自己调用它，不把某一次的 sha256 写死在脚本里。

Android 这边：

```
patches/apply-patches.sh /path/to/lineage-23.2
cd /path/to/lineage-23.2
source build/envsetup.sh
lunch lineage_kukui-trunk_staging-userdebug
m images
```

`out/target/product/kukui/super.img` 是系统分区的来源。`userdata` 不从构建物里拿，写盘时在 U 盘上新建空的 f2fs。

### zip 里有什么

zip 是给电脑用的安装包，里面没有 recovery 的 `update-binary`。depthcharge 不会执行那种包。

```
kukui-usb-<日期>.zip
  flash-usb.sh
  images/kernel.kpart
  images/android.kpart
  images/menu.kpart
  images/super.img
  images/MANIFEST
```

`MANIFEST` 每一行是 `名称 字节数 sha256`，外加两行命令行摘要，用来核对 USB FIT 里是 `11201000.usb`、eMMC FIT 里是 `11230000.mmc`。`flash-usb.sh` 先核对 zip 里的文件，再写盘。

### 写盘脚本做什么

调用时显式传入目标盘，例如 `flash-usb.sh /dev/sdX`。脚本按这个顺序拒绝：

1. 不是块设备，或者是分区节点而不是整盘。
2. 工作站的根分区、家目录所在盘，或者路径里出现 `nvme`。
3. 序列号或型号对上工作站那块 YMTC。
4. sysfs 里没有 USB。
5. 任一分区已经挂载。
6. 容量不在大约 32 GiB 到 256 GiB 之间。太小放不下 8 GiB 的 `super` 加数据分区。

通过之后打印型号、序列号和容量，等用户再确认一次。然后：

1. 新建上面那张 U 盘 GPT。`sgdisk` 不传 `-a`。这台机器上的 `sgdisk` 会把对齐数字当成磁盘名。
2. 内核槽的 GPT 属性：priority 15、tries 15、successful 1。写完从分区表读回这 64 位，对不上就停，此时还没写镜像。
3. 写入 `kernel.kpart` 和 `super.img`，按清单的长度读回并比对 sha256。
4. 格式化 `pmOS_boot`、`metadata`、`userdata`，`misc` 写零。把 `android.kpart` 和 `menu.kpart` 拷进 `/kukui-install/`。
5. 卸载目标盘。

脚本不重启平板，也不碰已经插在机器里的 eMMC。写完的使用方式和现在一样：开发者模式、允许 USB 启动、Ctrl+U。

### 实现步骤

1. 把内核打包和 `super.img` 展开收成 `bringup/release/build-images.sh`。输出目录里只有那四个镜像和 `MANIFEST`。不调用会清空磁盘的旧脚本。
2. 写 `bringup/release/flash-usb.sh`，只接受命令行上的那块盘，并做上面的拒绝条件。先在一块空 U 盘上跑通，读回四个哈希。
3. `bringup/release/pack-zip.sh` 把脚本和镜像打成 zip。zip 里的 `flash-usb.sh` 保持可执行位。
4. 用这张新 U 盘 Ctrl+U。桌面、Wi-Fi 和安装器能起来之后，才把 zip 当成可分发的安装盘。eMMC 在这一步不写。

## 2. 保留用户数据的更新

### 怎么更新

更新包比安装盘小，里面没有空的 `userdata`，也没有整盘 GPT。

```
kukui-update-<日期>.zip
  manifest.txt
  super.img
  android.kpart
  menu.kpart          # 菜单没变就可以不放
```

`manifest.txt` 写版本、四个文件里实际存在的那些的 sha256，以及它们要写到的分区名（`super`、`android_kernel`、`menu_kernel`）。安装器只认分区名和 sysfs 路径，不认 `mmcblk0p7` 这种序号。

使用时从 U 盘上的 Android 打开现在的安装器，多一个「更新系统」。包可以放在 U 盘的数据分区上，也可以放在 eMMC 的 `userdata` 里事先下载好。安装器：

1. 确认这次启动的盘是 `11201000.usb` / `11200000.usb`，目标盘是 `11230000.mmc`，而且两块不是同一个磁盘。
2. 核对 zip 里的哈希，以及 FIT 命令行。eMMC 那份必须是 `soc/11230000.mmc`。
3. 核对 eMMC 上已经有 `super`、`android_kernel`、`userdata`，并且 `userdata` 的文件系统是 f2fs。对不上就停，不格式化。
4. 把 `super.img` 写到名为 `super` 的那一个分区，读回整段 sha256。
5. 把 `android.kpart` 写到 `android_kernel`。分区属性原样留下。菜单 FIT 只有清单里带了才写，同样不改属性。
6. 不调用 `mke2fs`、`make_f2fs`、`sgdisk` 和 `resize2fs`。

属性必须留下。菜单能在下次开机出现，是因为 `menu_kernel` 的 priority 是 14 且 successful，两个系统槽的 priority 是 0。更新把某个槽写成 priority 15、successful 1 之后，depthcharge 会一直进那个槽，菜单不再出现。

`metadata` 留下，已有的锁屏和加密数据才能在新系统里打开。这一次更新不改加密格式。以后若要改，清单里单独写一项，安装器在动 `metadata` 之前再问一次，默认不碰。

Linux 根分区、Linux 内核槽和 `pmOS_boot` 不在这个包里。

### 为什么这一步从 U 盘启动

eMMC 上的 Android 正在使用的 `super` 已经挂到 device-mapper 上。把新镜像写进这块正在使用的分区，写到一半断电，下次就起不来。用户数据在另一个分区上，所以数据还在，但系统本身要靠 U 盘才能再写回去。更新本来就是在做这件事，所以第一次就放在已经能识别 `11230000.mmc` 的安装器里，不在正在运行的系统上写自己的 `super`。

下载可以在 eMMC 的系统里做。8 GiB 的包放到 `userdata`，然后 Ctrl+U，安装器从那里读取。U 盘 2.0 拷一整张 `super` 已经慢，更新包用 sparse 镜像，安装器在写入前展开到一个临时文件，展开后的长度仍必须是 8589934592。

### 在设备上更新，以及 recovery

这两条以后都能做，都不是第一版。

在 eMMC 系统里后台更新，走的是 virtual A/B：新系统先写成 `userdata` 上的快照，重启后由第一阶段 init 合并进 `super`。depthcharge 不用理解 Android 的 A/B 槽。要加的是 `update_engine`、`snapuserd`，以及 ramdisk 里合并快照的那段。内核 FIT 仍然得单独写进 `android_kernel`，而且不能改 GPT 属性。这是一套新的启动路径，等「从 U 盘换 super 和内核、用户数据还在」已经在这台上重复成功，再做。

recovery 也能做，形态是菜单里的第三项，或者一个平时 priority 为 0 的小 FIT。它从 `userdata` 或 U 盘读同一个更新 zip，规则和安装器相同。depthcharge 的开发者屏幕没有「进 recovery」这一项，音量键组合也进不了一个 `recovery.img`。标准 Lineage 的 `adb sideload` 还要把 Type-C 切成 gadget，而这份内核为了 U 盘启动把控制器留在 host。所以第一版不增加 recovery 分区，也不打开 USB gadget。

菜单第三项的价值是：更新包已经在 `userdata` 里时，可以不另外做一张安装盘。那是第 2 步的安装器跑通之后的减负，写盘规则不另起一套。

### 实现步骤

1. 给 `kukui-installd.sh` 加一条更新路径，和现有的「全新安装」「双系统安装」并列。入口先只接受本地 zip 路径。
2. 写分区之前把将要写入的分区名、父设备路径和「不格式化 userdata」打到状态文件里，界面原样显示。用户确认之后才 `dd`。
3. 用一张已知的 `super.img` 和 `android.kpart` 在现有 eMMC 上试一次。试完核对 `userdata` 的文件系统 UUID 没变，`pmOS_root` 的大小没变，`menu_kernel` 的 GPT 属性仍是 priority 14、tries 15、successful 1。
4. 重启进菜单，再进 Android。原来的账号、已装应用还在，新系统的行为符合这次镜像。Linux 仍能从菜单进入。
5. 这一步成功之后，再把同一个 zip 的下载放到 eMMC 系统里。应用只负责下到 `userdata` 并核对 sha256，然后提示拔下别的盘、Ctrl+U、在安装器里点更新。

## 完成之前不做的

- 不把 `payload.bin` 或 recovery 的 `updater-script` 当成这个包的格式。
- 不在 eMMC 系统里打开 USB gadget，也不为了 sideload 去抢 `11201000.usb`。
- 不在更新里重写分区表，不缩小 Linux 根分区，不格式化 `userdata`。
- 不把发布脚本接到 `write-sandisk.sh` 那条会清空目标盘、并且只认某一张读卡器的路径上。
