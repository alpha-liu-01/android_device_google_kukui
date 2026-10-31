# 阶段 0：基线

2026-10-30 结束。只读，没有写 U 盘，没有写 eMMC，没有换内核。机器是 `user@10.0.0.117`，这次启动的 `boot_id` 是 `38377700-ade5-454d-8d9a-42a738d00013`，采集时已开机 1 天 5 小时。路线图在 [roadmap.md](roadmap.md)。

## 身份

| 项 | 实测 |
| --- | --- |
| 型号 | `MediaTek krane sku176 board`。`compatible` 是 `google,krane-sku176`、`google,krane`、`mediatek,mt8183` |
| 发行版 | postmarketOS v26.06。桌面是 KDE Plasma，Wayland |
| 设备包 | `device-google-kukui` 13-r0。`/etc/deviceinfo` 是空的覆盖文件，生效的是 `/usr/share/deviceinfo/deviceinfo` |
| 内核包 | `linux-postmarketos-mediatek-mt81` 6.18.28-r0 |
| `uname` | `6.18.28-mt81 #1-postmarketos-mediatek-mt81 SMP PREEMPT Thu May 28 21:40:00 UTC` |
| 内存 | `MemTotal` 3,969,368 kB |
| zram | `/dev/zram0`，算法 zstd，5,968,184 KiB。采集时 swap 已用约 445 MiB |
| GPU | `13040000.gpu`，`mediatek,mt8183b-mali` / `arm,mali-bifrost`。驱动 `panfrost`，编进内核。`card1` 和 `renderD128` 都在。用户空间包是 `mesa-dri-gallium` |
| 安全芯片 | `/sys/class/tpm/tpm0`，TPM 2.0，挂在 SPI `1100a000.spi`。只服务引导 |

正在运行的命令行：

```text
cros_secure kern_guid=61e1577f-bd28-2941-90fc-972eb9557a1b quiet splash plymouth.ignore-serial-consoles plymouth.prefer-fbcon loglevel=2 pmos_boot_uuid=38f0e7d6-fa7d-471b-b14f-5236254f0be1 pmos_root_uuid=ff04cbc1-8e08-44f6-a4c6-07d487cbaa07 pmos_rootfsopts=defaults
```

`kern_guid` 就是下面 `mmcblk0p1` 的 `PARTUUID`。启动分区 UUID 是 `pmos_boot_uuid`，根分区 UUID 是 `pmos_root_uuid`。

`/usr/share/deviceinfo/deviceinfo` 把 FIT 几何定成：内核分区扇区 8192、长 65536、板名 `mt8183`、压缩 lzma、DTB 通配 `mediatek/mt8183-kukui*`。`/boot` 里已经有 `mt8183-kukui-krane-sku176.dtb`，61,542 字节，sha256 `852744daac3c6290009cb3dd5cb7f321aea10e29ab0526aa13b76f757f5503d5`。第一份 Android FIT 只用这一块。

## 磁盘

没有 SD 卡槽。eMMC 是 `mmcblk0`，整盘 116.5 GiB，父设备 `11230000.mmc`。根在这张盘上。采集时没有 U 盘，`lsblk` 里除了 eMMC、它的 boot 分区、8 MiB 的 SPI NOR（`mtdblock0`）和 zram，没有别的磁盘。SPI NOR 是固件闪存，不作为写入目标。

| 分区 | 起始扇区 | 扇区数 | 名称 | 文件系统 | `PARTUUID` |
| --- | --- | --- | --- | --- | --- |
| mmcblk0p1 | 8192 | 65536（32 MiB） | `pmOS_kernel` | 无 | `61e1577f-bd28-2941-90fc-972eb9557a1b` |
| mmcblk0p2 | 73728 | 1048576（512 MiB） | `pmOS_boot` | ext2，挂在 `/boot`，503.6 MiB | `979a9d26-4b71-8f4c-8b27-b7e02d0c0f3e` |
| mmcblk0p3 | 1122304 | 243154911 | `pmOS_root` | ext4，挂在 `/`，112.3 GiB，已用 6.1 GiB | `b1efe5e8-bd83-8e46-8cdf-a9c82a1ab27a` |

`/dev/mmcblk0p1` 属于 `root:disk`，当前用户不在 `disk` 组，`sudo` 和 `doas` 都要密码。原始内核分区的校验和这次没有读到。记下的是分区几何，以及 depthcharge 实际安装的那份 FIT 文件：

| 文件 | 字节 | sha256 |
| --- | --- | --- |
| `/boot/vmlinuz` | 13,487,996 | `be8714aafa8302548c176f3627bdbf5976a856aed0f33ceaf420b736c4b5af53` |
| `/boot/vmlinuz.kpart` | 24,723,456 | `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e` |

阶段 1 第一次拿到 root 时，先对 `/dev/mmcblk0p1` 做校验和，再写 U 盘。目标如果是 `mmcblk0`，不写。

以后插入的 U 盘会是 `mmcblk0` 以外的磁盘。当前根是 `mmcblk0p3`。

## 引导标志

`crossystem` 读到 `cros_debug = 1`，开发者模式是开的。`dev_boot_usb` 没有读到：系统里没有 `mosys`，`crossystem` 对这项报错。这次不安装软件包。阶段 1 写好 U 盘之后，用 Ctrl+U 验证；如果选不了 U 盘，再只改 `dev_boot_usb`，不刷其它固件。

## 内核配置

`/proc/config.gz` 不存在。配置在 `/boot/config`，9359 行。和 Android 直接相关的现状：

| 选项 | 现状 | 阶段 2 |
| --- | --- | --- |
| `CONFIG_ANDROID_BINDER_IPC` | `=y`，设备 `binder,hwbinder,vndbinder` | 保持。没有 Rust binder 这项 |
| `CONFIG_ANDROID_BINDERFS` | 未设置 | 打开 |
| `CONFIG_SECURITY_SELINUX` | 配置里没有这一项。`CONFIG_LSM` 不含 selinux | 打开，并打开 `CONFIG_SECURITY_NETWORK`（现在未设置） |
| `CONFIG_SECURITYFS` | `=y` | 保持 |
| `CONFIG_CPUSETS` | `=y` | 保持 |
| `CONFIG_CPUSETS_V1` | 未设置 | 打开。缺了会在亮屏前重启 |
| `CONFIG_EROFS_FS` | `=m`，模块文件 `erofs.ko.zst` | 改成编进内核 |
| `CONFIG_EXT4_FS`、`CONFIG_F2FS_FS` | `=y` | 保持 |
| `CONFIG_FS_ENCRYPTION` | 未设置 | 打开。userdata 加密要用 |
| `CONFIG_BLK_DEV_DM`、`CONFIG_DM_CRYPT` | `=y` | 保持 |
| `CONFIG_DM_VERITY` | `=m` | 先留着 |
| `CONFIG_NF_TABLES` 及 `nft_ct`、`nft_masq` 等 | 模块 | 保持模块，阶段 3 在 `netd` 之前加载 |
| `CONFIG_USB_CONFIGFS`、`CONFIG_USB_F_FS` | 模块。`CONFIG_USB_CONFIGFS_F_FS=y` | 阶段 3 不用 gadget。装 eMMC 时再加载 |
| `CONFIG_USB_MTU3`、`CONFIG_USB_XHCI_HCD`、`CONFIG_USB_GADGET` | `=y` | 保持 |
| `CONFIG_DRM_MEDIATEK`、`CONFIG_DRM_PANFROST` | `=y` | 保持 |
| `CONFIG_ZRAM` | `=y` | 保持 |
| `CONFIG_CFI`、`CONFIG_SHADOW_CALL_STACK` | 都已经是 `=y` | 保持。阶段 2 只加选项，不要把这两项关掉 |
| `CONFIG_DRM_ITE_IT6505` | `=y` | 驱动在，运行中的设备树里没有这个节点 |
| `CONFIG_MEDIATEK_WATCHDOG` | `=m`，已加载 | 见下面的休眠 |
| `CONFIG_VIDEO_MEDIATEK_VCODEC` | `=m`，已加载 | 见视频 |

## 显示

`card0` 来自 `mediatek-drm`，唯一连接器是 `card0-DSI-1`，状态 connected。KScreen 报的模式是 `1200x1920@60.00`，当前模式，也是首选模式。几何在 1.5 倍缩放下是 1280×800，对应逻辑分辨率 1920×1200。旋转值是 2，即逆时针 90°，和设备树里的 `rotation = <270>` 是同一件事。

扫描输出是竖屏 1200×1920。用户看见的横屏是合成器转出来的。刷新率是整数 60.00 Hz，不是 Gru 那种 60.015 Hz。`config_defaultRefreshRate` 先用 60，阶段 4 如果滑动被锁到 30 fps 再改。

Android 产品按用户看见的 1920×1200、密度 240 写。`drm_hwcomposer` 要带上这块面板的旋转，否则画面是竖的。

背光是 `/sys/class/backlight/backlight_lcd0`，raw，采集时 277/1023。平台设备 `backlight_lcd0`。

## 输入

| 设备 | 节点 | 位置 |
| --- | --- | --- |
| Whiskers Tablet Mode Switch | `event0` | EC `cros-cbas`。开关位是 `SW_TABLET_MODE` |
| `cros_ec_buttons` | `event1` | 电源键和音量键 |
| `hid-over-i2c 27C6:0E30` | `event5` | Goodix，I2C `0-005d`。触摸 |
| 同设备 Stylus | `event6`、`event7` | 笔。另有一个 `UNKNOWN` 节点 `event8` |
| Google Inc. Hammer | `event3`、`event4` | USB `18d1:503c`。键盘和触控板 |

笔和触摸在同一颗 Goodix 上。笔有自己的电量计 `hid-0018:27C6:0E30.0003-battery`，采集时 88%、Discharging。底座当时接在机器上，Hammer 已经枚举。`/dev/input/event*` 属于 `input` 组，这次没有读到开关的当前值。

## 音频

声卡 0：`mt8183_mt6358_ts3a227_max98357`。UCM 在 `/usr/share/alsa/ucm2/MediaTek/mt8183/mt8183_mt6358_ts3a227_max98357/HiFi.conf`。

| 用途 | PCM |
| --- | --- |
| 扬声器 | `hw:0,0`（`Playback_1`）。开机混音器把 `DL1` 接到 `I2S3` |
| 耳机 | 同一个 `hw:0,0`。`HiFi.conf` 里耳机也是 device 0，靠 ADDA 混音器切换 |
| 内置麦 | `hw:0,5`（`Capture_3`）。UCM 打开 `MTKAIF_DMIC` |
| 耳机麦 | 同一个 `hw:0,5` |
| HDMI | `hw:0,7`（`Playback_HDMI`）。这份 UCM 没有用它 |

`hw:0,1`、`hw:0,2` 和另外几路采集存在，HiFi 配置没有引用。阶段 4 按这份 UCM 写策略，不要照 Gru 那样给喇叭和耳机各分一个 ALSA device。

## 无线

Wi-Fi 是 SDIO `mmc1:0001:1`，控制器 `11240000.mmc`。`ath10k_sdio` 日志：

```text
qca6174 hw3.2 sdio target 0x05030000 chip_id 0x00000000 sub 0000:0000
firmware ver WLAN.RMH.4.4.1-00174 api 6
```

SDIO vendor `0x0271`，device `0x050a`。`wlan0` 已连上，采集时地址 `10.0.0.117/24`。固件在 `/lib/firmware/ath10k/QCA6174/hw3.0/`，文件名是 `firmware-sdio-6.bin.zst` 和 `board-2.bin.zst`。设备树里的校准变体是 `LE_Krane`，板文件用 `board-2.bin`。

蓝牙是 `hci0`，驱动 `hci_uart` + `btqca`，rfkill 未屏蔽。内核日志：

```text
Bluetooth: hci0: QCA Downloading qca/nvm_00440302_i2s_eu.bin
```

磁盘上的文件是 `/lib/firmware/qca/nvm_00440302_i2s_eu.bin.zst`。Android 的 firmware loader 不认 `.zst`，镜像里放解压后的副本。

## USB

只有一个 USB 控制器：`11201000.usb`，兼容串 `mediatek,mt8183-mtu3`，驱动 `mtu3`。xHCI 子节点是 `11200000.usb`，总线 Bus 001，USB 2.0。

内部 hub `05e3:0610` 在 `1-1`。Hammer 键盘在 `1-1.1`，走这个 hub。`/sys/class/udc` 是空的，没有注册 gadget。

Type-C 是 EC 上的 `port0`。采集时插着一个 PD 电源：`power_role` 当前是 sink，电压 4.875 V，`usb_type` 当前是 `PD`。`data_role` 当前显示为 device，伙伴类型 `not_dfp`。控制器仍以 host 驱动着内部 hub，所以这个 data role 没有把键盘拆掉，也没有产生 UDC。

eMMC 的 `androidboot.boot_devices` 用 `11230000.mmc`。U 盘会挂在 `11200000.usb` 下面。阶段 1 插入 U 盘后再核对块设备的父设备，fstab 仍按 GPT 分区名找，不写死 `sda`。

## 外接显示和视频

运行中的设备树里没有 `ite,it6505`。`/sys/bus/i2c/drivers/it6505` 只有驱动，没有绑上的设备。DRM 只有 DSI-1。这颗 6.18 的 Krane 设备树没有把 IT6505 打开。外接显示不放进前四个阶段。

`/dev/video*`：

| 节点 | 名字 |
| --- | --- |
| video0 | `mtk-mdp3:m2m` |
| video1 | `mtk-jpeg-enc` |
| video2 | `mtk-vcodec-enc` |
| video3 | `mtk-vcodec-dec` |

解码器的设备树兼容串是 `mediatek,mt8183-vcodec-dec`，平台设备 `16020000.video-codec`。`mtk_vcodec_dec` 拉起了 `v4l2_h264` 和 `v4l2_vp9`。没有 `/dev/v4l-subdev*`，设备树里也没有摄像头或 ISP 节点。摄像头不在这颗内核的板级描述里，阶段 5 不补一个不存在的传感器。

## 电源和传感器

| 节点 | 驱动 | 采集时 |
| --- | --- | --- |
| `sbs-12-000b` | `sbs-battery`，EC I2C tunnel `i2c-12` 地址 `0x0b` | 型号 `L16D2P3`，100%，Charging，4.392 V，充电电流 274 mA，`charge_full` 6714 mAh，循环 71 次，温度 25.1°C |
| `CROS_USBPD_CHARGER0` | `cros-usbpd-charger` | Charging，online，`current_max` 3 A |
| `hid-...-battery` | Goodix HID | 笔的电量，不是整机电池 |

传感器：`cros-ec-accel`、`cros-ec-gyro`、`cros-ec-light`，都在 `cros-ec-sensorhub` 下面。另外有 MT6358 和 auxadc 的 IIO，以及两个 thermal zone。

## 休眠

`mem_sleep` 当前选中 `deep`。`/sys/power/state` 和 RTC `wakealarm` 只有 root 能写，logind 的 `CanSuspend` 返回 `challenge`。这次没有再发起一次休眠，避免机器睡下去又没有唤醒闹钟。

同一次启动里已经有记录：`success=11`，`fail=2`。最后一次失败是 2026-10-30 22:11，`panfrost 13040000.gpu: PM: failed to suspend: error -16`（`-EBUSY`），`last_failed_step=suspend`。失败之后 SSH 还在这同一个 `boot_id` 上，所以上次失败回到了同一次启动，没有停在 bootloader。11 次成功也在这同一天的启动里。

看门狗是 `10007000.watchdog` 上的 `mtk_wdt`，模块已加载。不按 Gru 的方式从第一份镜像开始喂 `/dev/watchdog`。阶段 4 再测 Android 里的休眠；若 Panfrost 仍以 `-EBUSY` 拒绝，修的是这颗 GPU 的 suspend，不是看门狗保活。

## 阶段 2 之前不变的事

eMMC 分区表就是上面那张。`vmlinuz.kpart` 的 sha256 保持 `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e`，直到阶段 1 用 root 补上原始分区校验和。内核仍是 6.18.28-r0。
