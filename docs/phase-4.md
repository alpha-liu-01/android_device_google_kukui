# 阶段 4：平板日常

2026-10-31 开始。路线图在 [roadmap.md](roadmap.md)。阶段 3 的第十四次 Ctrl+U 已经进入桌面，记录在 [阶段 3](phase-3.md)。这一段仍用内核 `6.18.28-mt81-kukui2`，`#1-kukui-phase2`。不重链内核映像，不改版本字符串，不写 eMMC，不启用 USB gadget，不喂看门狗。镜像保持 vanilla。

## 第十四次启动已经有的

zygote 在内核时间 24.06 秒启动，开机动画在 28.85 秒起来，`sys.boot_completed=1` 在 55.48 秒。SurfaceFlinger 报 Mali-G72 (Panfrost)、OpenGL ES 3.1 Mesa 25.3.3。路线图里「第一帧先用软件渲染，确认加速后再拿掉 SwiftShader」这一步不做：这台机器从阶段 3 起就是 Panfrost，镜像里没有 SwiftShader。

蓝牙 HAL 在那次启动里崩溃。`vendor.bluetooth-default` 在 48.63 秒收到 SIGABRT，`initializationComplete` 的状态不是成功。当时镜像里没有 QCA UART 模块和固件。阶段 3 已经把 `persist.sys.disable_rescue=true` 放进系统属性，那次没有恢复出厂。后来的结果写在休眠一节之后。

117.08 秒 SurfaceFlinger 把显示设成 power mode 0。随后用户空间冻结被拒绝，先是 300 个任务，再是 308 个，任务恢复。日志写到 122.00 秒。这是没有输入时的灭屏，不是崩溃重启。休眠是这一段的最后一项，现在不改。

## 为什么 U 盘能启动，鼠标却不能用

U 盘和鼠标在同一颗 xHCI 上，`11200000.usb`，父节点是 `11201000.usb` 的 mtu3。U 盘走 `usb-storage`。鼠标和键盘盖走 HID。两条驱动不互相占用这颗控制器。

第十四次日志里内核已经看见这三样设备：

- 0.85 秒 `usbhid: USB HID core driver`。USB HID 编进内核，不是模块。
- 1.82 秒 `input3`，`Google Inc. Hammer`，`18d1:503c`。这是键盘盖，接在内置 hub `05e3:0610` 的 1-1.1。
- 5.30 秒 `input6`，`Logitech USB Receiver Mouse`，`046d:c52b`。接收器接在外接 hub `214b:7250` 的 1-1.2.3。同一只接收器还有键盘 `input5`、Consumer Control `input7`、System Control `input8`。
- 5.57 秒 Goodix `27C6:0E30`，I2C `0-005d`。`input11` 是触摸，`input12` 和 `input13` 是笔，`input14` 是 UNKNOWN。
- `hid-generic.ko`、`hid-multitouch.ko`、`i2c-hid-of-goodix.ko` 都在 5.3 到 5.6 秒加载成功。键盘盖的第二接口先被 hid-generic 建成 `input4`，再被 hid-multitouch 建成 `input10`。那是触控板，节点出现之后再看事件。

Android 的 InputReader 不读这些 input 设备本身，只打开 `/dev/input/event*`。节点由 `evdev` 创建。配置是 `CONFIG_INPUT_EVDEV=m`。`drivers/input/evdev.ko` 已经编好，没有依赖，vermagic 是 `6.18.28-mt81-kukui2 SMP preempt mod_unload aarch64`，文件时间 2026-10-30 20:06。它不在 ramdisk 的 `modules.load` 里，这次日志也没有加载它。

所以 ueventd 在 15.87 秒做完 coldboot 时，`/dev/input` 还不存在，没有节点可建。17.05 秒 init 报 `Could not add watch for /dev/input: No such file or directory`。触摸、外接鼠标、键盘盖走的是同一条缺口，所以一起不能用。

`CONFIG_UHID=m` 的 `uhid.ko` 是虚拟 HID，这三样实体设备不靠它。`CONFIG_INPUT_UINPUT=y` 已经编进内核。

## 第一项已写入

`evdev.ko` 放在 `modules.load` 和 `modules.dep` 的第一行，没有依赖。ramdisk 里是 55 个模块。内核映像没重链，时间仍是 2026-10-31 01:18:48，版本仍是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2`。super 没动。

新 FIT 12,513,280 字节，读回 `sdb1` 的 sha256：

```text
0fe8a90405415e72ec7a3cf51abe290cf0fc2ce4ad63d9bb2da51f5ab6aea1fb
```

写入之后核对过内置盘：postmarketOS v26.06，`/boot/vmlinuz.kpart` 的 sha256 仍是 `15b59e3aed9710dd8bc0fbd789929c340daf973b9edf7ba98ed67e18ec3cf03e`。

## 第十五次启动

Ctrl+U 进入桌面，设置向导能走完。`evdev.ko` 在 5.31 秒加载。外接罗技鼠标和键盘盖触控板能用。SurfaceFlinger 仍是 Mali-G72 (Panfrost)、OpenGL ES 3.1 Mesa 25.3.3。内核映像没变。日志 279666 字节，2487 行，sha256 `6988c6daf350255b86d839677659a296e460b73a30d357b86981b28a8f23b6eb`，写到 181.61 秒。

Launcher3 大约每秒崩溃一次，线程是 `launcher-loader`：`AppWidgetManager.getInstalledProvidersForProfile` 空指针。和 Gru 上的是同一处。`config_enableAppWidgetService` 默认是 false，镜像里又没有 `android.software.app_widgets`，`AppWidgetService` 不会起来。上一份 userdata 日志里 Seedvault 也因 `IBackupManager` 空指针崩溃过，同样是缺 `android.software.backup`。这次按 Gru 那份软件特性清单补进 vendor，没有开 zram，没有声明摄像头和传感器。

触摸屏的内核节点还在。5.76 秒 Goodix `27C6:0E30` 注册成 `input11`，笔是 `input12` 和 `input13`。外接鼠标能用，所以不是 `evdev` 没加载。给这个节点加了 IDC：`device.internal = 1`，`touch.deviceType = touchScreen`。笔和 UNKNOWN 用的是别的名字，这份 IDC 不套到它们身上。方向先不动，等这次能点到屏幕再对。

内核分区没重写。新的 super 仍是 8,589,934,592 字节，读回 `sdb3` 的 sha256：

```text
e191b3d61e67cfce595033be81b7ebd4c31df89c5f0f5c2909f92482096b9535
```

写入时平板不在网上，eMMC 没有重新核对。

## 第十六次启动

Launcher3 停住了，不再反复退出。触摸屏能带动界面。手指从屏幕右侧往左滑，系统里是从上往下。这是多出来的 90 度，不是镜像。Goodix `27C6:0E30` 的节点 `event5` 已经读到 `/vendor/usr/idc/hid-over-i2c_27C6_0E30.idc`。这次把 `touch.orientation` 写成 `ORIENTATION_270`，用来抵消这一下。`orientationAware` 保持默认打开。若下次变成镜像或方向仍不对，再改成 `ORIENTATION_90`。

SDIO 卡在 0.98 秒起来：`mmc1: new UHS-I speed SDR104 SDIO card at address 0001`。驱动没有绑定，日志里没有 ath10k。固件和模块放进这份 super：`board-2.bin`、`firmware-sdio-6.bin` 在 `/vendor/firmware/ath10k/QCA6174/hw3.0/`，七个模块在 `vendor_dlkm` 的 `/lib/modules/`，`post-fs` 里按 rfkill、cfg80211、libarc4、mac80211、ath、ath10k_core、ath10k_sdio 的顺序 `insmod`。内核映像没重链，时间仍是 2026-10-31 01:18:48。

日志 241079 字节，2239 行，sha256 `27dc02050cc5d25272a9a968478db18af4f20cecd532af0e822c70fdc1f1154c`，写到 94.037 秒。

内核分区没重写。新的 super 仍是 8,589,934,592 字节，读回 `sdb3` 的 sha256：

```text
161935a9ed289c45dcb0c8bb6efb5a9495866a415d560727cc4ba73fda8b4c16
```

写入时 `10.0.0.117` 没有路由，eMMC 没有重新核对。

## 第十七次启动

触摸方向对了。Wi-Fi 仍然没有。SDIO 卡还是 0.98 秒起来，日志里没有 ath10k，也没有 `cfg80211` 的监管库提示。`dlkm_loader` 报 module load count 是 0。`init.kukui.rc` 的 `early-init`、`init`、`fs`、`post-fs-data` 都执行了，`post-fs` 没有。上一份里的 `insmod` 写在 `post-fs`，所以没有加载。

这次改由已经在跑的 `dlkm_loader` 加载。`vendor_dlkm` 的 `/lib/modules/` 加上 `modules.load` 和 `modules.dep`，顺序是 rfkill、cfg80211、libarc4、mac80211、ath、ath10k_core、ath10k_sdio。固件路径在 `on init` 再写一次，写在 loader 启动之前。内核映像没重链。

桌面没有导航键，也没有手势。AOSP 的 `config_showNavigationBar` 默认是 false，这台机器没有硬件导航键，键盘盖又不是常驻的。vendor 覆盖把它改成 true。三键和手势两套 overlay 本来就在镜像里，设置里可以切换。默认先出三键。

日志 274270 字节，2474 行，sha256 `057b48778adec9b7e7587bf4eaef1f364f35492d1b88a104049f667b766ad2d0`，写到 191.47 秒。

内核分区没重写。新的 super 仍是 8,589,934,592 字节，读回 `sdb3` 的 sha256：

```text
228d2e06fa17f4514ad3aa75089e7a96f561a0ce7664fe4ea57369ef5b5f4850
```

写入时没有再核对 eMMC。

## 第十八次启动

导航栏在。Wi-Fi 开关打开后立刻弹回去。驱动这次是好的：`dlkm_loader` 加载了模块，25.06 秒 `ath10k_sdio` 认出 `qca6174 hw3.2`，固件 `WLAN.RMH.4.4.1-00174`。`wificond` 建出 `wlan0`，接口是 up。随后 `WifiNative` 报 `Failed to setup iface in supplicant`，接口被拆掉。开关再拨几次都是同一句。

`wpa_supplicant` 加 STA 接口之前要有 `/vendor/etc/wifi/wpa_supplicant.conf`，再抄到 `/data/vendor/wifi/wpa/wpa_supplicant.conf`。这份 super 里没有那个模板，所以加接口直接失败。镜像里补上这份配置，并关掉 P2P。logcat 过滤加上 `wpa_supplicant` 和 `SupplicantStaIfaceHalAidlImpl` 的警告。内核映像没重链。

日志 254984 字节，2360 行，sha256 `106fd90cfa4c07ce89fbffe095ed5868b60269d6213cc90908e029fe90feae22`，写到 134.02 秒。

内核分区没重写。新的 super 仍是 8,589,934,592 字节，读回 `sdb3` 的 sha256：

```text
012a698619d23a36de96b46517a654c87f4066bc375d313fa54dc8014a9806b5
```

写入时没有再核对 eMMC。

## 第十九次启动

Wi-Fi 可用。无线 adb 先配对 `10.0.0.104:41895`，再连上 `10.0.0.104:5555`。`wlan0` 是 up，地址 `28:cd:c4:70:77:b3`，IPv4 `10.0.0.104/24`，默认路由 `10.0.0.1`。IPv6 前缀 `2607:fea8:4f03:3700::/64`，默认路由是路由通告里的 `fe80::1e9e:ccff:fe5a:8543`。连的是 `"Not 6GHz"`，WPA2，802.11ac，5765 MHz，RSSI -38，发送 702 Mbps，接收 866 Mbps，分数 100，supplicant 状态 `COMPLETED`。`ping 1.1.1.1` 两包都回来，往返大约 24.4 ms。这次没有把 U 盘拔回来抄 kmsg，上面是正在运行的系统。

USI 笔已经能画。节点是 `hid-over-i2c 27C6:0E30 Stylus`，`event6`，类型已经是 touchscreen，方向仍是 `Rotation0`。手指那路用的是另一个名字，所以笔没有读到 `ORIENTATION_270`。笔从右往左画时，系统里仍是从上往下。配置写成 `hid-over-i2c_27C6_0E30_Stylus.idc`，方向同样是 `ORIENTATION_270`。userdata 里也有一份同内容的文件。内核映像没重链。

内核分区没重写。新的 super 仍是 8,589,934,592 字节，读回 `sdb3` 的 sha256：

```text
f3a260c441cc5468f4403d2de7eed6f3859370fc4a9b871cf0d07cf76df2ba5f
```

写入时没有再核对 eMMC。

## 第二十次启动失败，分区头已清零

手写笔方向已经对，工作符合预期。

电量和充电提前做。正在运行的系统里，模块没加载时电源类只有 Goodix 笔的 HID 电池，范围是设备，电量 0。Health 只在启动时扫一次电源，而且跳过设备范围的电池，所以界面停在 0%，跟电流表有没有电流无关。

`sbs-battery.ko` 和 `cros_usbpd-charger.ko` 是这颗内核已经编好的模块，vermagic 仍是 `6.18.28-mt81-kukui2 SMP preempt mod_unload aarch64`。当场 `insmod` 之后，`sbs-12-000b` 报电量 93%，电压 4.344 V，电流大约 +1.0 A，状态 Charging，温度 28.3°C。EC 充电状态是交流在线，电池充电电压上限 4400 mV，充电电流上限 3500 mA，输入电流上限 3000 mA。化学成分读出来是 `<unkn>`，因为 EC 的 I2C 隧道没有 `I2C_FUNC_SMBUS_READ_BLOCK_DATA`，电量数字不受影响。这次启动里 Health 已经扫过，界面仍是 0%。下次 Ctrl+U 时 `dlkm_loader` 在 Health 之前加载这两个模块。

5 V 和 9 V 是另一件事。EC 固件是 `krane_v2.0.2771-7a68c38973`，2022-11-24。EC 控制台里，开机后大约 4.2 秒请求了充电器的 PDO 2，`9000mV 3000mA`，充电限流到了 `v9000`。6.4 秒出现 `Handle sleep: 0`，随后改请求 PDO 1，`5000mV 3000mA`，并停在那里。充电器两种 PDO 都有。关机和进系统前的 9 V 就是 EC 自己谈成的；AP 起来之后 EC 自己把请求降到 5 V。

这版固件的主机命令表里没有 `EC_CMD_EXTERNAL_POWER_LIMIT`（0x00A2）。v0 和 v1 都返回 `EC_RES_INVALID_COMMAND`。`EC_CMD_PD_EXCHANGE_STATUS` 和 `EC_CMD_TYPEC_STATUS` 也不在表里，所以进系统之后请求停在 5 V / 3 A。电池侧的上限是 4.4 V、3.5 A。充电器在谈 9 V 之前已经把 VBUS 限制设到 12850 mV，9 V 在这个范围里，但这版固件没有把抬高请求的命令交给主机。

新的 super 把这两个模块放进 `vendor_dlkm` 的 `modules.load`，顺序在 ath10k 后面。内核映像没重链，时间仍是 2026-10-31 01:18:48。写入目标是读卡器 `Generic MassStorageClass` 序列号 `000000002959` 上的 119.1 GB SanDisk，不是 YMTC 那块盘。写之前这张卡是空的 exfat，卷标 `SandiskEX`。内核槽仍是原来的 FIT，类型是 ChromeOS kernel，属性是 priority 15、tries 15、successful。`pmOS_boot` 是新建的 ext4。super 是 8,589,934,592 字节，读回 `sdb3` 的 sha256：

```text
566a770c1bb4983973f7eb531fb105f183580efa35c5bbcee0ee63c95de36c21
```

写入时没有再核对 eMMC。

两次 Ctrl+U 都在几秒内回到开发者屏幕。内核和第一阶段 init 都起来了，`pmOS_boot` 挂上了。metadata 和 userdata 的开头不是全 0 也不是全 0xff，是原来 exfat 留下的数据，所以 superblock 无效。Android 只在分区开头 4 KiB 全 0 或全 0xff 时才把 formattable 分区格式化。这两次都没有格式化。`/data` 仍是只读的 system erofs，`keystore2` 收到 SIGABRT，`init_user0` 失败。日志是 `work/phase4/kukui-phase4-sandisk-boot1.log` 和 `kukui-phase4-sandisk-boot2.log`。

已经把 metadata、misc、userdata 各自的开头 1 MiB 写成 0。内核槽和 super 没动，上面的 sha256 仍然有效。下次 Ctrl+U 应能自己格式化这两个分区。

## 人工测试

分区头清零之后，卡从工作站卸载再做。平板里的旧 U 盘先留着。

1. 卸下新的 SanDisk，插到 Krane 的 hub 上。外接鼠标仍接在 hub 上，键盘盖装上。
2. 重启，开发者屏幕按 Ctrl+U。这次应能过 metadata 和 userdata，不再几秒就回到开发者屏幕。
3. 电量百分比不应再停在 0%。应接近这次读到的 93%，并显示正在充电。电流表在进系统之后仍会停在 5 V，这是 EC 固件的行为，不是电量计没装上。
4. Wi-Fi 上次已经连上 `"Not 6GHz"` 并能 ping 通。不用再为开关弹回做一次测试。笔的方向已经对。
5. 再重启，不要按 Ctrl+U。应回到 eMMC 上的 postmarketOS v26.06。
6. 把新卡插回工作站。日志在 `pmOS_boot` 的 `kukui-phase3.log`。

## USB 睡眠断电

可以在从 U 盘启动时保留睡眠，不必先装进 eMMC。

`s2idle` 和 `deep` 都会进 `xhci_mtk_suspend` 和父设备 `mtu3` 的 suspend。两边都会把 USB 端口设成掉电，再关掉 PHY 和时钟。3.3 V 的 `vusb` 是 `regulator-always-on`，读卡器灯灭是端口和 PHY 掉电，不是这路 LDO。启动盘、super 和 `/data` 都在这颗控制器上，总线一掉电，同一次启动就结束。写一次 `mem` 之后机器以 `reboot` 重新起来，运行时间回到大约一分钟，睡眠计数是 0。

`CONFIG_USB_XHCI_MTK` 和 `CONFIG_USB_MTU3` 都是 `=y`。运行时的 `power/control` 挡不住系统睡眠。两个驱动现在看同一个 `suspend_power_off`：`0` 时睡眠不给这颗控制器掉电，`1` 时保持原来的掉电。内存里的默认值是 `0`。节点是 `/sys/devices/platform/soc/11201000.usb/suspend_power_off`。

设置里增加了「USB 睡眠供电」。开关打开就是睡眠时断电。选择写在 `/data/system/kukui_usb_suspend_power_off`，下次启动由 `kukui-usb-suspend.sh` 写回节点。系统盘如果还在这个 USB 口上，打开开关会再次出现灯灭、唤醒后回到开机动画。

新的 `Image.gz` 用 clang-21 编过，版本字符串是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2 SMP PREEMPT Sat Oct 31 19:07:02 EDT 2026`。设置应用 `KukuiUsbSuspend` 在 `system_ext/priv-app`。2026-10-31 只把新的 FIT 和 super 写进 SanDisk（序列号 `000000002959`）的内核槽和 super。metadata、misc、userdata 和 `pmOS_boot` 没动，分区头的校验和写前写后相同。卡已卸载。还没有这次 Ctrl+U，不能当作已经能睡眠。

内核槽读回 sha256 `75c6397799f1e1402083d222f71d669ca24dad67fb318a642c434a41dd884c99`。super 读回 sha256 `766466a22301fb2854610ad922b987f3316b380d5af95fd6fe3f8634c0acde24`。

默认是睡眠时不断电。设置里的「USB 睡眠供电」关掉就是这个默认。系统盘还在这张卡上时不要打开它，打开会再次把读卡器掉电。电流表在进系统之后仍会停在 5 V。

2026-10-31 这次 Ctrl+U 用的是上面那对镜像。节点存在且值为 0，应用也装上了。页面看起来是空的，是因为 `Theme.DeviceDefault.Settings` 把内容画在标题栏下面，开关和说明都被盖住。开关实际是关的。睡眠仍然把读卡器掉电，唤醒后回到开机动画：`xhci_mtk_suspend` 虽然跳过了端口掉电，`xhci_bus_suspend` 仍会把端口设成 U3。

随后的内核在标志为 0 时也跳过 `xhci_bus_suspend` 和对应的 resume。版本字符串是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2 SMP PREEMPT Sat Oct 31 19:34:51 EDT 2026`。设置页改成没有标题栏遮挡。2026-10-31 把这两份写进 SanDisk。开关能看见，并且是关的，睡眠仍然把读卡器掉电，唤醒后卡在开机动画。这次日志停在 `Freezing user space processes aborted`，设备挂起还没开始，所以只跳过 `xhci_bus_suspend` 不够。读卡器仍会因为 USB 自动挂起或 `deep` 睡眠掉电。

下一版内核在标志为 0 时做三件事：禁止这条 USB 总线上的自动挂起和远程唤醒，系统睡眠只用 `s2idle`，并且继续跳过端口掉电。版本字符串是 `#1-kukui-phase2 SMP PREEMPT Sat Oct 31 19:57:12 EDT 2026`。命令行增加 `mem_sleep_default=s2idle`。2026-10-31 只重写了内核槽。super 仍是上一版，设置页不用换。metadata、misc、userdata、`pmOS_boot` 和 super 的开头 1 MiB 校验和写前写后相同。

内核槽读回 sha256 `2154be92f68851d32dfc2842f98c26ee8f3e899508cd60ac3b06526f0ca90e24`。super 仍是 `b50c6a6274acd6d1033c8165b9bb044123e58ee532cdafa1c5178ceeea295d5e`。

2026-10-31 这次 Ctrl+U 之后，锁屏时读卡器灯保持常亮，唤醒后仍是同一次启动。无线 adb 还在 `10.0.0.104:5555`。运行时间超过 500 秒，没有回到开机动画。`suspend_power_off` 是 0，`/sys/power/mem_sleep` 是 `[s2idle] deep`。`suspend_stats` 是 `success=3`、`fail=1`，失败的那次停在 `freeze`，`last_failed_errno=-16`。

日志里 0.885 秒和 22.999 秒都有 `suspend_power_off=0, mem_sleep=s2idle`。72.988 秒冻结被打断，72.993 秒 `PM: suspend exit`。随后三次进了设备挂起：73.226 秒、88.566 秒、113.473 秒都打印了 `USB bus stays in U0` 和 `leave USB powered`。113.343 秒有 `PM: suspend entry (s2idle)`。每次从冻结到 `Restarting tasks` 大约 1 秒。73.363 秒 EC 报 `EC detected sleep transition timeout. Total sleep transitions: 0`，这次警告只打一次。114 秒之后到至少 517 秒，`success` 仍是 3，没有新的 `suspend entry`。118.9 秒 SurfaceFlinger 把屏幕电源模式设成 0，那是灭屏，不是又一次 s2idle。睡眠过程中 Wi-Fi 断开，119.3 秒重新关联。

所以内核确实进过 s2idle，而且 USB 没有掉电，唤醒后还是同一次启动。它没有在灭屏期间一直停在 s2idle 里，EC 也没有计到一次完整的睡眠切换。

## 蓝牙

这颗芯片的蓝牙是 UART 上的 `qcom,qca6174-bt`，挂在 `11003000.serial`。设备树里的 NVM 文件名是 `nvm_00440302_i2s_eu.bin`。内核配置里 `bluetooth`、`hci_uart` 和 `btqca` 都是模块，镜像里原先没有这些 `.ko`，也没有 `/vendor/firmware/qca`。所以 HAL 打开 HCI 失败，`initializationComplete` 不是成功，接着在 `FD_SET` 里用了 -1。

2026-10-31 这次开机没有换内核。从内置盘只读拷出固件并解压，再加载和当前内核版本匹配的模块。内核日志：

```text
Bluetooth: hci0: QCA controller version 0x00440302
Bluetooth: hci0: QCA Downloading qca/rampatch_00440302.bin
Bluetooth: hci0: QCA Downloading qca/nvm_00440302_i2s_eu.bin
Bluetooth: hci0: QCA setup on UART is completed
```

下载过程中有两次 `Frame reassembly failed (-84)`，设置仍然完成。`/dev/rfkill` 原来是 `0600 root`，HAL 的 uid 和 gid 都是 `bluetooth`，打不开。改成 `bluetooth:bluetooth` `0660` 之后重新打开蓝牙。`dumpsys bluetooth_manager` 是 `enabled: true`，`state: ON`，名字是 Lenovo IdeaPad Duet。`com.android.bluetooth` 保持运行，崩溃日志没有新增。

2026-10-31 只把这份 super 写进 SanDisk（序列号 `000000002959`）。里面有这两份固件、蓝牙模块，以及 `bluetooth.le.disable_apcf_extended_features=1`。Rome 3.2 不支持那条扩展查询。大小 `8589934592`。读回 sha256 `1c2511c8ff7920cc834719c993b9875517e183988a9dc5cfb56be100a805ab78`。内核槽、`pmOS_boot`、metadata、misc 和 userdata 的开头 1 MiB 校验和写前写后相同。卡已卸载。还没有这次 Ctrl+U，不能当作开机后蓝牙自己会起来。

## 顺序

前一项能用再做下一项。

1. `evdev.ko` 已加载。外接鼠标和键盘盖触控板能用。
2. Panfrost。第十五次启动仍是 Mali-G72 GLES 3.1。
3. Wi-Fi 和无线 adb。第十九次已连上 `"Not 6GHz"`，`10.0.0.104`，无线 adb 可用。
4. 触摸、旋转、USI 笔。手指和笔的方向都已经对。屏幕导航键已打开。
5. 底座键盘、触控板，以及拆下底座后的平板模式。Hammer 已经在 `input3`。Whiskers 的 Tablet Mode Switch 在 `input0`，`cros_ec_buttons` 在 `input1`，都在 1 秒内注册。
6. 背光。
7. 蓝牙。QCA6174 走 UART `qca6174-bt`。2026-10-31 这次开机手动加载模块后，内核下载了 `qca/rampatch_00440302.bin` 和 `qca/nvm_00440302_i2s_eu.bin`，日志是 `QCA setup on UART is completed`。`dumpsys bluetooth_manager` 为 `state: ON`，名字是 Lenovo IdeaPad Duet，打开后超过 7 分钟没有新的崩溃。模块、固件和 `/dev/rfkill` 权限已写入 SanDisk 的 super，读回 sha256 `1c2511c8ff7920cc834719c993b9875517e183988a9dc5cfb56be100a805ab78`。内核槽没换。还没有这次 Ctrl+U。
8. 扬声器播放，然后是内置麦和 3.5 mm 耳机孔。
9. 电量和充电。电量计模块已放进 super。9 V 请求要等 EC 固件有对应的主机命令，这一版 `krane_v2.0.2771` 没有。
10. zram。
11. 休眠和唤醒。开关为关时走 `s2idle`，USB 保持供电。2026-10-31 这次 Ctrl+U 已确认：读卡器灯常亮，`suspend_stats` `success=3`，日志有 `PM: suspend entry (s2idle)`，唤醒后仍是同一次启动。每次停留大约 1 秒，EC 计到的睡眠切换是 0。不预先喂看门狗。

## 完成标准

在 4 GB 内存上完成一次「开机、联网、打开网页、安装应用、睡眠、唤醒」。唤醒后仍是同一次启动。网页不是黑的。

## 这一段不做

不写 eMMC，不启用 USB gadget，不把 SELinux 改成 enforcing，不做视频解码、摄像头和 IT6505。不改内核版本字符串。不把 Gru 的触摸和键盘补丁搬过来：那台是 RK3399，输入芯片不同。
