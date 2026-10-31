# Kukui 移植 LineageOS 23.2

第一台机器是正在 eMMC 上运行 postmarketOS 的 Google Krane（Lenovo IdeaPad Duet）。目标是让它用原厂 depthcharge，先从 U 盘进入 LineageOS 23.2（Android 16），内置 eMMC 上的 postmarketOS 留作退路；这套系统能日常使用之后，再装到 eMMC。同一张 FIT 以后可以带上 Kukui 家族的其它板，没有实机的型号标成未验证。

Android 17 是这套板级工作做完之后的换源码，不和第一台机器的启动并行。

## 结论

沿用这台机器已经在跑的 `linux-postmarketos-mediatek-mt81` 6.18.28-mt81，以及 depthcharge 从 U 盘启动。图形走 `mtk-drm`、Mesa Panfrost 和 `drm_hwcomposer`。无线走已经在用的 ath10k SDIO。

不刷 UEFI，不替换只读固件，不换内核系列。U 盘上的系统能重复启动、日常功能完成之前，不写 eMMC。

已经同步的源码是 `/run/media/alpha/YMTC/lineage-23.2`。板级文件放在这个仓库，再逐个文件链进那棵树。Soong 不跟随目录符号链接。不继承 Android 树里的 `device/google/gru` 或 `device/google/trogdor`。Gru 那份设备树是产品形态的样板，芯片相关的项全部换掉。Gru 的阶段记录在 [docs_from_googlegru](docs_from_googlegru/roadmap.md)。

## 这台机器

2026-10-30 在 `user@10.0.0.117` 上核对过。细节、校验和和内核配置在 [阶段 0](phase-0.md)。

| 项 | 实测 |
| --- | --- |
| 型号 | Google Krane sku176，`google,krane-sku176`。Lenovo IdeaPad Duet |
| 发行版 | postmarketOS v26.06，KDE Plasma，Wayland |
| SoC | MT8183。4× Cortex-A73，4× Cortex-A53 |
| GPU | Mali-G72，`panfrost` 编进内核，`renderD128` 存在 |
| 内存 | `MemTotal` 3,969,368 kB。zram 5.7 GiB，zstd |
| 内置盘 | eMMC `mmcblk0`，116.5 GiB，父设备 `11230000.mmc`。根是 `mmcblk0p3`，ext4 112.3 GiB |
| 外置盘 | 采集时没有 U 盘。根就是 `mmcblk0`，插入的 U 盘会是另一块磁盘 |
| 面板 | DSI-1 扫描 `1200x1920@60.00`。Plasma 旋转后逻辑分辨率 1920×1200，缩放 1.5。密度按 240 |
| 背光 | `backlight_lcd0`，raw，采集时 277/1023 |
| 触摸 / 笔 | Goodix `27C6:0E30`，I2C `0-005d`。触摸和笔是同一颗 HID，笔自带电量计 |
| 键盘 | `Whiskers` 平板模式开关在 EC 上。键盘和触控板是 USB `18d1:503c`（Hammer），接在内部 hub `05e3:0610` 后面 |
| 音频 | 声卡 `mt8183_mt6358_ts3a227_max98357`。扬声器和耳机都是 `hw:0,0`，两个麦都是 `hw:0,5`，靠混音器切换 |
| Wi-Fi | QCA6174 hw3.2 SDIO，`ath10k_sdio`，固件 `WLAN.RMH.4.4.1-00174`。文件在 `ath10k/QCA6174/hw3.0/`，是 `.zst` |
| 蓝牙 | `hci0`，`hci_uart` + `btqca`，固件 `qca/nvm_00440302_i2s_eu.bin`，磁盘上是 `.zst` |
| USB | 唯一控制器 `11201000.usb`（`mtu3`），xHCI `11200000.usb`，USB 2.0。采集时 Type-C 是 PD 受电，`/sys/class/udc` 为空 |
| 外接显示 | 驱动 `CONFIG_DRM_ITE_IT6505=y`，运行中的设备树没有这个节点，DRM 只有 DSI-1 |
| 电池 / 充电 | `sbs-12-000b` 型号 `L16D2P3`。充电器 `cros-usbpd-charger` |
| EC / 安全芯片 | `cros-ec` SPI。`tpm0` 是 TPM 2.0 |
| 视频 / 摄像头 | `mtk-vcodec-dec` 在 `/dev/video3`，同时加载了 `v4l2_h264` 和 `v4l2_vp9`。没有传感器节点 |

引导是 ChromeOS depthcharge。postmarketOS 这个设备包把几何定成：内核分区从扇区 8192 起、长 65536 扇区（32 MiB），板名 `mt8183`，压缩 lzma。板名用 `mt8183` 是因为 FIT 里可以放多块 DTB，而工具在板名 `kukui` 时会选错。第一份镜像里只放 `mt8183-kukui-krane-sku176.dtb`。

内核包是 `linux-postmarketos-mediatek-mt81`，`uname` 为 `6.18.28-mt81`。工作站上 `/home/alpha/Downloads/pmaports-c49c00d09d1c9e266bd8c8e8ddae6e7255a5ee94` 里的同名包是 6.12.57，只用来核对启动几何和补丁名单，不作为 Android 的内核基线。

## 和 Gru 能沿用多少

两台机器共用的是 ChromeOS 平板的启动方式，以及 Android 在主线内核上的用户空间骨架。芯片、显示、无线总线、USB 和开发盘都要重做。

### 整段沿用

这些是方法。

- 外置介质做试验，eMMC 留着现在的 postmarketOS。开发者模式下，超时或 Ctrl+D 进内置盘，Ctrl+U 进 U 盘。完成标准里始终包含「再选内置盘还能进桌面」和「eMMC 内核分区校验和不变」。
- 内核分区是带 ChromeOS 头的 FIT，不是 `boot.img`。板名 `mt8183`，压缩 lzma。构建时加 `--root none`，否则工具会把当时系统的根 UUID 写进命令行。`depthchargectl` 会加上 `kern_guid=%U`。
- 命令行保留 `console=tty0`。不写 `root=` 或 `pmos_root_uuid`，除非这一步故意要挂 postmarketOS。
- 内核从这台机器已经验证过的 6.18.28-mt81 源码和配置往上加 Android 选项，不换版本。本地版本字符串用来和发行版内核区分。
- 设备树继承 LineageOS 的 mainline 公共部分，本仓库只放 Kukui 的板级差异。
- 4 GB 内存：默认镜像不带 GApps，打开 zram。
- cr50 / H1 只服务引导。Android 密钥用软件 KeyMint 和软件 Gatekeeper。第一份镜像就带 device manifest，避免 `keystore2` 崩溃把机器打回选盘界面。
- bringup 期间 SELinux permissive。enforcing 放到日常功能都通了之后、可分发镜像之前。
- 健康、灯、电源用 AIDL 示例 HAL 接到电池、背光和充电器。Wi-Fi 用 `nl80211` 的 `wpa_supplicant`。
- 固件文件先核对许可证，放未压缩的副本。Alpine 上的 `.zst` 不能直接给 Android 的 firmware loader。
- `lunch` 写成 `lineage_kukui trunk_staging userdebug`。少写 `trunk_staging` 时，userdebug 会被当成 release。
- 不设置 `TARGET_INITIAL_BRINGUP`。那个开关会选中 HIDL `drmfb-composer`。图形用 AIDL `drm_hwcomposer`。
- 动态 super：system、vendor、system_ext、product 和 dlkm 用 erofs，并且 `first_stage_mount`。userdata 用 f2fs，metadata 用 ext4。userdata 在 first stage 就可写。

Gru 上已经证明、和芯片无关、第一份镜像就要带上的用户空间修复：

- 命令行不写 `binder.impl=rust`。继续用 C binder。`device/mainline/common` 的默认命令行带这一项，要拿掉。
- `system/core` 里用 `F_GET_SEALS` 判断 memfd，不再对沙箱进程做 `readlink("/proc/self/fd")`。Gru 上不改的话，WebView 和浏览器是黑的。
- 打开 `CONFIG_CPUSETS_V1`。6.12 以后 cgroup v1 的 cpuset 是单独开关，缺了会在亮屏前重启。
- 刷新率先写成 60。阶段 0 量到的模式是整数 `60.00` Hz。阶段 4 如果滑动被锁到 30 fps，再把 `config_defaultRefreshRate` 调高。
- 不打开「内置屏承载桌面」。Gru 上这项会在每次开机的最近任务里留下两张「桌面设备」。这台机器的外接屏还没做，先不设。

### 必须按 Krane 重做

| 层 | Gru（Scarlet） | 这台 Krane |
| --- | --- | --- |
| SoC / 内核 | RK3399，`linux-postmarketos-rockchip` 6.6.34 | MT8183，`linux-postmarketos-mediatek-mt81` 6.18.28 |
| DTB | `rk3399-gru-scarlet-kd.dtb` | `mt8183-kukui-krane-sku176.dtb` |
| depthcharge 板名 | `gru` | `mt8183` |
| 开发盘 | microSD，独立的 mmc 控制器 | U 盘。唯一的数据口是 USB 2.0，控制器是 `11201000.usb` |
| 内核分区 | 32 MiB，lzma | 同样是 32 MiB，lzma。FIT 装不下就减 initramfs，不加大分区 |
| GPU | Mali-T860，Panfrost Midgard | Mali-G72，Panfrost Bifrost。GLES。先不打开 Vulkan |
| 显示 | `rockchip-drm`，竖屏扫描 1536×2048 | `mtk-drm`，扫描 1200×1920，安装旋转 270。用户看到的是横屏 1920×1200 |
| gralloc | minigbm generic，背后是 rockchip dumb | minigbm 用 Panfrost / generic。不用 msm，也不用 rockchip 那份 |
| 压缩缓冲 | rockchip AFBC 试过，原子提交失败，屏是黑的 | postmarketOS 的 mt81 树里有一份关掉 MediaTek AFBC 的补丁。基线内核已经带着的就保留，bringup 期间不再打开 |
| 无线 | `ath10k_pci`，QCA6174 | `ath10k` SDIO，变体 `LE_Krane` |
| 蓝牙 | `btusb` | UART `qca6174-bt` |
| 音频 | `rk3399-gru-sound`（DA7219 + MAX98357A） | `mt8183_mt6358_ts3a227_max98357`。扬声器、耳机是 `hw:0,0`，麦是 `hw:0,5` |
| 触摸 / 笔 | Elan I2C + 独立的 Wacom HID | Goodix `27C6:0E30`，触摸和笔在同一颗 HID 上 |
| 键盘 | 无可拆底座 | `cros-cbas` + 内部 USB hub 上的键盘和触控板 |
| 视频 | Hantro / rkvdec，无状态 V4L2 | `mtk-vcodec-dec`，已加载 `v4l2_h264` 和 `v4l2_vp9`。不搬 rkvdec 补丁 |
| 外接显示 | `cdn-dp` + `rockchip/dptx.bin` | 这颗设备树没有 IT6505 节点。内置屏完成之前不做 |
| 看门狗 | RK3399 的 `dw_wdt`。6.6 上一休眠就死在 bootloader，所以 Android 从启动就喂 `/dev/watchdog` | `mtk_wdt`。这次启动里 deep 休眠成功 11 次，失败 2 次都回到了同一次启动。Android 不从第一份镜像开始喂看门狗 |
| 盘容量 | eMMC 约 29 GiB，super 后来按 SD 做成 8 GiB | eMMC 约 112 GiB。开发期 super 按 U 盘算，8 GiB 够 vanilla 镜像。写 eMMC 时不必为了 32 GB 盘去缩小 |

Gru 这些补丁不要打到这颗内核或这份 HAL 上：Rockchip I2S 在 S3 之后主时钟锁不住、Kingdisplay 的 EoTp、DA7219 和数字麦抢同一根 I2S 线、`dw_wdt` 喂食、rkvdec 的 NV12 跨距、VP9 的上一帧运动矢量、cdn-dp 的图层缩放。它们对应的现象如果在这台上出现，按这台的驱动重新查。

AIDL 音频 HAL 里两处是 AOSP 的行为，和声卡无关，写 Krane 的策略时要一起处理：`XsdcConversion` 会把内置麦的 `address` 改成 `bottom`；外部设备要在 `populateConnectedDevicePort` 里接受策略文件里已经声明的端口。扬声器和耳机都打开 `hw:0,0`，两个麦都打开 `hw:0,5`，切换靠 UCM 里的混音器。

## 软件栈

| 层 | 选择 |
| --- | --- |
| 引导 | 现有 depthcharge。板名 `mt8183`，压缩 lzma。Ctrl+U 从 U 盘启动 |
| 内核 | 这台机器的 6.18.28-mt81，加 Android 配置片段。不升 postmarketOS，不换 6.12 |
| 图形 | `mtk-drm` + Panfrost + Mesa + `drm_hwcomposer` + minigbm。渲染 `skiagl`。Vulkan 先关 |
| 无线 | mac80211 / ath10k SDIO，Android Wi-Fi HAL 走 nl80211 |
| 蓝牙 | 内核里的 `qca6174-bt`，固件按实机日志里的文件名打包 |
| 音频 | 现有 MT6358 + TS3A227E + MAX98357A，AIDL 音频 HAL |
| 电源 | `sbs-battery` 和实机上的充电器节点，接到 health HAL |
| 输入 | 触摸、笔、电源键、音量键、底座键盘和触控板走 evdev。底座拆装走 `cros-cbas` |
| 密钥 | 软件 KeyMint、软件 Gatekeeper |
| 分区 | U 盘上的 Android 用动态 super。内核分区仍由 depthcharge 启动 |
| 调试 | U 盘启动期间 USB 控制器是 host，有线 adb 不可用。日志写在 U 盘已有的 `pmOS_boot` 上，无线 adb 从 Wi-Fi 起来之后开始用 |
| 策略 | bringup 期间 permissive |

Android 16 的官方通用内核是 6.12。6.18 比它新，Gru 那种「内核太旧、VINTF 拒绝启动」不应再出现。若兼容矩阵仍然拒绝这串版本，只放宽这项检查，不因此换内核。缺的具体 eBPF 帮助函数到时候单独 backport。

这颗内核已经打开 `CONFIG_CFI` 和 `CONFIG_SHADOW_CALL_STACK`。阶段 2 保持这两项，不要为了排查启动把它们关掉。

## 阶段

每一段都有退出标准。没达到之前不开始下一段的实现。每一段开始时再写自己的阶段文档；这份路线图保持总览。

写盘脚本若发现目标是当前根分区所在的磁盘，直接退出。eMMC 的分区表和内核分区校验和在每次写入前后各记一次。

### 0 基线

已结束。记录在 [阶段 0](phase-0.md)。eMMC 未写。采集时没有插入 U 盘。

### 1 启动契约

已结束，记录在 [阶段 1](phase-1.md)。用和 eMMC 上同一份 6.18.28-mt81，把 U 盘启动到一个只写标记的 init。不挂 postmarketOS 的根，不写 eMMC。

U 盘和 eMMC 是同一份 GPT（eMMC 由 `dd` 装上），UUID 分不出两块盘，`sdb3` 后面也没有空余扇区。不新建 `bootlog`。日志写到 U 盘已有的 `pmOS_boot`，文件 `/kukui-phase1.log`。init 只认 `sd*` 上 `PARTNAME=pmOS_boot` 的分区。

FIT 使用这份 `vmlinuz` 和 `mt8183-kukui-krane-sku176.dtb`，压缩 lzma。这台机器的 `depthchargectl` 板名用 `krane`（镜像里只有这一块 DTB）。命令行是 `kern_guid=%U console=tty0 loglevel=7 deferred_probe_timeout=30`。`depthchargectl check` 通过后，在工作站上写入 U 盘内核分区，不改 GPT 优先级。

完成标准：

1. 开发者屏幕上 Ctrl+U 之后，U 盘 `pmOS_boot` 的 `/kukui-phase1.log` 里有 `kukui-android phase1` 和完整内核日志。进到用户空间点亮屏幕之前面板可以是黑的。
2. 不按 Ctrl+U，postmarketOS v26.06 进到图形会话。
3. eMMC 的分区表和内核分区校验和不变。

### 2 Android 内核配置

已结束，记录在 [阶段 2](phase-2.md)。在 6.18.28-mt81 的源码上只增加 Android 需要、而这颗源码里存在的选项。本地版本字符串用来和发行版内核区分。不关 postmarketOS 正在用的项。源码里没有的符号不加。

阶段 0 已经对过 `/boot/config`。这次要打开的是：`CONFIG_EROFS_FS`（现在是模块，改成编进内核）、`CONFIG_SECURITY_SELINUX`、`CONFIG_SECURITY_NETWORK`、`CONFIG_ANDROID_BINDERFS`、`CONFIG_CPUSETS_V1`、`CONFIG_FS_ENCRYPTION`。`CONFIG_SECURITYFS`、ext4、f2fs、device-mapper、dm-crypt、Panfrost、zram、CFI 和 shadow call stack 已经编进内核，保持。`CONFIG_USB_CONFIGFS_F_FS` 已经是 `=y`，configfs 本身仍是模块，阶段 3 不用 gadget。netfilter 保持模块，阶段 3 在 `netd` 之前加载。源码里没有的符号不加，不关 postmarketOS 正在用的项。

这一段不装 Android。U 盘上没有现成的第二套 Linux 用户空间，所以不重复 Gru 那种「先启动 Debian」。init 仍然只写日志，日志里要能看出新的本地版本，以及 SELinux、erofs、binderfs、cpuset v1 已按上面的方式编好。模块装到 U 盘上单独的目录，不写 eMMC 的 `/lib/modules`。

完成标准：Ctrl+U 能写出带本地版本标记的日志；回到内置盘仍是 v26.06；eMMC 校验和不变。休眠不在这一段测。

### 3 亮屏

镜像已写入 U 盘。第十一次 Ctrl+U 背光常亮但没有画面，人强制关机。合成器和 DSI-1 已经起来，开机动画的 EGL 窗口在 Panfrost render 节点上分配失败。gralloc 改到 `card0`。`netd` 因缺少 bpf/policy 匹配反复退出并杀掉 zygote，这些匹配已放进 ramdisk。等待下一次 Ctrl+U。记录在 [阶段 3](phase-3.md)。

用阶段 2 的内核，在 U 盘上启动第一份 Android。源码树在 `/run/media/alpha/YMTC/lineage-23.2`。产品名 `lineage_kukui`，平板、仅 Wi-Fi。用户看见的画面是 1920×1200、密度 240。DRM 扫描是 `1200x1920@60.00`，合成器要做阶段 0 里那次旋转。

命令行在阶段 1 的基础上加上 `androidboot.selinux=permissive androidboot.hardware=kukui printk.devkmsg=on`。`lsm=` 里 selinux 在 bpf 前面，否则 bpf 的空 `setprocattr` 会让 init 的 `setexeccon` 得到 EINVAL。`androidboot.boot_devices` 用 `soc/11201000.usb/11200000.usb`：阶段 1 里 U 盘是这个 xHCI 上的 `sda`，init 要比对去掉 `/devices/platform/` 之后的整段路径。eMMC 那份是 `11230000.mmc`，这一段不用。不写 `binder.impl=rust`。fstab 按 GPT 分区名找 super、metadata、userdata 和 misc，不写死 `sda`。

`bootlog` 保留。后面的分区改成 super、metadata、userdata、misc。写入前先把分区表发出来，确认目标是 U 盘再写。eMMC 不写。

从启动就打开的模块只包括亮屏需要的：面板、`mtk-drm`、Panfrost、触摸、EC 键盘，以及 netd 还依赖的 nftables。erofs、ext4、f2fs 和 device-mapper 已经编进内核。USB gadget 这一段不启用，避免和 U 盘 host 抢控制器。

完成标准：

1. Ctrl+U 后面板上出现画面。
2. `bootlog` 里 zygote 和 surfaceflinger 已经起来。有线 adb 不作为通过条件。
3. 回到内置盘，v26.06 仍在，eMMC 校验和不变。

大约两分钟仍然全黑时，回到内置盘读 `bootlog`，不把黑屏本身当成内核已坏。

### 4 平板日常

按这个顺序补。前一项能用再做下一项。镜像保持 vanilla。

1. Panfrost 加速。第一帧可以先用软件渲染把画面救出，确认加速之后从镜像里拿掉 SwiftShader。
2. Wi-Fi，然后是无线 adb。这是后面改用户空间的通道。U 盘还插在机器上，有线 adb 仍然不可用。
3. 触摸、旋转、USI 笔。
4. 底座键盘、触控板，以及拆下底座后的平板模式。
5. 背光。
6. 蓝牙。
7. 扬声器播放，然后是内置麦和 3.5 mm 耳机孔。
8. 电量和充电。
9. zram。
10. 休眠和唤醒。阶段 0 里失败停在 Panfrost 的 `-EBUSY`，机器仍回到同一次启动。这一项不预先喂看门狗。

完成标准：在 4 GB 内存上完成一次「开机、联网、打开网页、安装应用、睡眠、唤醒」。唤醒后仍是同一次启动。网页不是黑的。

### 5 收尾

日常路径通了之后，按实机现象处理，不把 Gru 的芯片补丁提前打进来。

- SELinux 改成 enforcing。Gru 上这一步暴露过的、需要在这台机器上重新写路径的有：`vendor_init` 加载模块、surfaceflinger 读显示 uevent、devtmpfs 上内核创建节点、memfd 在改标签之前被音频和蓝牙映射。genfs 按这台的 sysfs 路径写。
- 视频解码。解码器是 `mtk-vcodec-dec`，并且已经加载 `v4l2_h264` 和 `v4l2_vp9`。按这条无状态接口接 codec2，不搬 rkvdec 的补丁。
- 摄像头。这颗设备树没有传感器节点，这一段不造一个。
- IT6505 外接显示器。运行中的设备树没有这个节点。内置屏的旋转和合成先稳定，确认节点出现之后再做。
- 刷新率、开机动画、自动熄屏这类产品细节，按实机显示结果改。

完成标准：设置里 SELinux 正在运行，阶段 4 的各项仍在。enforcing 下复现的故障记进 `docs/bugs.md`，修完再进阶段 6。

### 6 可分发的 U 盘镜像

本仓库提供打包脚本和安装说明：开发者模式、`dev_boot_usb`、Ctrl+U、写入 U 盘、校验和。FIT 里是已经验证的 `krane-sku176`。

完成标准：按文档从零写入一张 U 盘可以启动。eMMC 上的 postmarketOS 仍在。

### 7 同族

`device-google-kukui` 还覆盖 kodama、kakadu、burnet，以及 jacuzzi 系的 fennel、juniper 等。放进同一张 FIT 只表示固件能选中，不表示用户空间已经配好。面板、音频功放、键盘和传感器方向按板子改。没有实机的型号标成未验证。

完成标准：除这台 Krane sku176 外，至少一台 Kukui 用同一张 U 盘进入桌面。没有第二台机器时，这一段保持未开始，不挡住 eMMC。

### 8 eMMC

U 盘上的 Android 必须能重复启动。写之前把 eMMC 分区表和内核分区再对一遍阶段 0 的记录，并在移动硬盘上留一份可恢复的内核分区副本。112 GiB 的盘按实盘重算分区，super 可以维持 8 GiB。

命令行里的 `androidboot.boot_devices` 改成 `11230000.mmc`。这一步才把 Type-C 做成有线 adb、MTP 和 OTG。改完的内核不再用于「从 U 盘当根文件系统」的那张 FIT，否则 U 盘和 gadget 会抢 `11201000.usb`。对外发布的 U 盘镜像保持 host，用来在 eMMC 写坏时启动。

完成标准：从 eMMC 进入桌面，阶段 4 的功能仍在，有线 adb 可用。U 盘上的恢复镜像仍能 Ctrl+U 启动。

## 明确后做

- Android 17：把同一份 `device/google/kukui` 换到新的 Lineage 源码树上
- OTA
- GApps、Widevine
- 没有机器在手上的 Kukui / Jacuzzi 型号
- Vulkan

## 这个仓库

这里放路线、板级设备树、local manifest、补丁和 U 盘打包脚本。LineageOS 树在 `/run/media/alpha/YMTC/lineage-23.2`。

当前进度：阶段 0、阶段 1 和阶段 2 已结束，见 [阶段 0](phase-0.md)、[阶段 1](phase-1.md) 和 [阶段 2](phase-2.md)。阶段 3 第十一次启动背光常亮但没有画面。gralloc 改到显示卡，netd 需要的 iptables 匹配已装进 ramdisk，等待下一次 Ctrl+U，见 [阶段 3](phase-3.md)。
