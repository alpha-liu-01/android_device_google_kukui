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

2026-10-31 只把这份 super 写进 SanDisk（序列号 `000000002959`）。里面有这两份固件、蓝牙模块，以及 `bluetooth.le.disable_apcf_extended_features=1`。Rome 3.2 不支持那条扩展查询。大小 `8589934592`。读回 sha256 `1c2511c8ff7920cc834719c993b9875517e183988a9dc5cfb56be100a805ab78`。内核槽、`pmOS_boot`、metadata、misc 和 userdata 的开头 1 MiB 校验和写前写后相同。卡已卸载。

同日这次 Ctrl+U 之后，蓝牙在开机时自己打开，崩溃次数是 0。蓝牙鼠标能用。蓝牙耳机的 A2DP 已连接，编码是 AAC、44100 Hz、立体声，媒体策略也选中了这只耳机，音量不是 0。`A2dpOffloadEnabled` 是 false，声音要走软件编码。正在跑的音频 HAL 仍是 `android.hardware.audio.service-aidl.example`。耳机连上时 `AHAL_StreamBluetooth` 打了 `applyParam failed`，A2DP 状态停在 Connected，没有进入 Started。播放器报过 `PLAYING`，进度停在 0，耳机没有声音。扬声器、麦克风和耳机孔还没接上这颗声卡，蓝牙音频留到那一项，不在这份示例 HAL 上单独修。

## 传感器

触摸和 USI 笔已经能用。AIDA64 读的是 Android 传感器接口。这次开机里 `sensorservice` 报 `No Sensors on the device`。EC 上的加速度计、陀螺仪和光感是 `cros-ec-accel`、`cros-ec-gyro`、`cros-ec-light`，驱动是模块，镜像里没有。也没有传感器 HAL。平台设备在 `cros-ec-sensorhub` 下面，模块没加载时不会出现在 IIO 里。

同一张正在跑的内核上加载了这几个模块。加速度计是 `iio:device4`，名字 `cros-ec-accel`，标签 `accel-display`。一次采样 raw 是 x=1015、y=6616、z=4990，`scale` 是 `0.001197100`，合起来大约 1 g。陀螺仪是 `iio:device5`。光感是 `iio:device6`，有 `in_illuminance_input`。内核没有 `in_mount_matrix`。

postmarketOS 在 Krane 上要把屏幕旋转从差 90 度拉正，udev 矩阵是 `0, 1, 0; -1, 0, 0; 0, 0, -1`。合成器已经用 `ORIENTATION_270` 把 1200×1920 的扫描转成横屏，那组矩阵是给「桌面自己再转一次屏」用的。叠在 `ORIENTATION_270` 上会再转 90 度。

2026-10-31 这次 Ctrl+U 之后，正放时画面是竖屏，显示内容的上方在物理屏幕的右侧。`dumpsys window` 是 `ROTATION_90`，分辨率 1200×1920。加速度计读数大约是 x=7.88、y=-1.10、z=-6.02，矩阵确实生效了，横屏的上方被报到了 +X。同一姿势改成单位矩阵之后，读数是 x=1.11、y=7.87、z=6.05，旋转回到 `ROTATION_0`，分辨率 1920×1200。这次是运行中改的配置，重启会丢。

读数慢是另一件事。加速度计本身大约 25 Hz。陀螺仪关掉之后 ODR 仍停在 200 Hz，`hwfifo_timeout` 是 0。EC 的 FIFO 是共用的，超时为 0 时要等队列满了才往上送，所以加速度计一次攒几百毫秒。这个节点是 `0644 root`，HAL 写不进去。把陀螺仪 ODR 写成 0、超时写成 0.01 秒之后，加速度计按大约 40 毫秒一笔送到 `sensorservice`。

下一份 super 用单位矩阵。`hwfifo_timeout` 交给 `system`。关掉传感器时把 ODR 写成 0，打开时把超时写成不超过 0.01 秒。2026-10-31 只把这份 super 写进 SanDisk（序列号 `000000002959`）。大小 `8589934592`。读回 sha256 `44e7b35f059e05ee4fd0fe8bf9e8cba52bff0bbb144eb729527183e0d10d2e90`。内核槽、`pmOS_boot`、metadata、misc 和 userdata 的开头 1 MiB 校验和写前写后相同。卡已卸载。

同日这次 Ctrl+U 之后，正放是横屏。`dumpsys window` 是 `ROTATION_0`，分辨率 1920×1200。vendor 里的矩阵是单位矩阵，没有 bind。加速度计大约是 x=1.16、y=7.82、z=6.11，合起来约 1 g，上方在 +Y。`sensorservice` 收到的间隔大约 40 毫秒，不再一次攒几百毫秒。加速度计 ODR 是 25 Hz，缓冲区开着，`hwfifo_timeout` 是 0.010 秒，节点是 `0660 system`。陀螺仪缓冲区关着，ODR 是 0，超时也是 0.010 秒。HAL 进程没有退出。内核日志里没有 EC FIFO 丢样。`WindowOrientationListener` 的缓存是 0。

SELinux 仍是 permissive。`hal_sensors_default` 读 IIO sysfs 有 AVC，后面标着 `permissive=1`，这次没有拦住读写。enforcing 时要给这条 sysfs 补规则，留到那一项。

2026-10-31 那次开机用的是当时编进镜像的 `android.hardware.sensors@2.1-gru-subhal`，外面是 `android.hardware.sensors-service.multihal`。它只认加速度计和陀螺仪。光感模块会加载，不进 HAL。`settings` 里 `accelerometer_rotation` 原来是 0，这次开机已经写成 1。2026-11-01 起源码在 `device/google/kukui/hal/sensors`，模块名是 `android.hardware.sensors@2.1-kukui-subhal`。单位矩阵和 FIFO 超时没有改。`device.mk` 不再把 `device/google/gru` 加进 Soong。卡上的 super 还是改名之前编的那一份。

## 音频

这台 Krane sku176 的声卡是 `mt8183_mt6358_ts3a227_max98357`。`krane.dtsi` 只包含 `mt8183-kukui-audio-max98357a.dtsi`，没有 `ts3a227e` 节点，也没有 `mediatek,headset-codec`。上游 UCM 写明 Krane 没有耳机孔：compatible 里有 `google,krane` 时不启用 Headphones 和 Headset。这台机器没有 3.5 mm 插孔，这一项测不了。

同一份设备树里，带 TS3A227E 的板才有插孔检测：kodama，以及 jacuzzi 的 burnet、cozmo、juniper-sku16、kappa、kenzo、pico、pico6、willow-sku1、fennel-sku7、fennel14-sku2、makomo-sku1。它们和 Krane 用同一类 MT6358 声卡，耳机和耳麦的混音器按 UCM 写进 HAL，策略里对应端口不挂成常驻设备。这份 FIT 只有 `mt8183-kukui-krane-sku176.dtb`，那些板开不了这张卡。没有实机，不把耳机孔记成可用。

DA7219 的板是另一颗 codec：damu、fennel sku1/sku6、fennel14、makomo-sku0、willow-sku0、kakadu、katsu-sku32。MT6358 的混音器对它们不适用。这份镜像不覆盖它们。kakadu-sku22 和 katsu-sku38 的设备树只接了 rt1015p，没有耳机 codec，也不当成有插孔。

扬声器和耳机播放都是 `hw:0,0`。内置麦和耳麦都是 `hw:0,5`。扬声器打开 `I2S3_CH1 DL1_CH1` 和 `I2S3_CH2 DL1_CH2`。内置麦打开 `MTKAIF_DMIC`、`Mic Type Mux=2`，以及 UL3 的两路 ADDA。`ro.vendor.audio.route=kukui` 时走这条路径。没设这个属性时仍走 Gru 的 DA7219。

音频相关驱动是模块。AFE 要 `audiosys` 复位，复位控制器在 `mtk_wdt` 里。加载这个模块是为了复位，不是为了喂看门狗。驱动注册时会打印 `Watchdog enabled`。这次开机 `WDT_MODE_EN` 没有置位，没有新的喂狗进程。已有的 `[watchdogd]` 是内核锁死检测。不要打开 `/dev/watchdog`。USB 声卡还要 `mc.ko`，`snd-usb-audio` 才能解析 `media_*`。这台只有一个 USB 2.0 口，启动盘就在上面。USB 耳机要经 hub 接，不能把 SanDisk 拔掉。

正在跑的 HAL 是 `android.hardware.audio.service-aidl.example`，策略原来指向 Cuttlefish，不认这张卡。A2DP 上次能连上但没声音：`standby()` 只在 `DISABLED` 时成功，第二次参数更新失败之后 `transfer()` 把 PCM 丢掉。已经改成端口已在 `STANDBY` 或 `STARTED` 时也算成功。还没在耳机上听过。

2026-10-31 只把第一份音频 super 写进 SanDisk（序列号 `000000002959`）。读回 sha256 `8540e0a73a11cc2526552afa4713b98f297a641ba14598963325e05e3c58c4b7`。同日这次 Ctrl+U 之后，声卡 0 和 USB 声卡都在，扬声器策略也指向 `CARD_0_DEV_0`。压缩音频没有声音：`c2.android.vorbis.decoder` 在 `MediaCodec.start` 报 `NO_MEMORY`。`/dev/ion` 不存在，`/dev/dma_heap/system` 也不存在，codec2 要的 system heap 没编进内核。同一段 PCM WAV 能写进 HAL，`DL1`、`I2S3` 和 MAX98357A 的 `HiFi Playback` 都会变成 On。USB 声卡被策略看见之后，`servicemanager` 拒绝注册 `IModule/usb`，因为 APEX 清单里这一项是注释掉的。蓝牙 A2DP 能打开流，但 AudioFlinger 写出的帧数是 0，和压缩解码没产出 PCM 一致。

同一段 440 Hz WAV 能从扬声器出来，但调节音量之后的第一次播放整段都是毛刺，立刻再播同一段就干净。内置扬声器仍走模拟器那条软件时钟：`start()` 之后音量命令和路由把第一块缓冲推迟了，时钟一旦落后就把后面每个 burst 整段丢掉。第二次播放开始得及时，就不再丢。这和 Gru 上 USB 声卡的非阻塞 `MonoPipe` 丢帧是同一类问题，只是扬声器当时被软件 `usleep` 盖住了。Kukui 的播放改成直接阻塞写 ALSA，由 MT8183 的时钟节流，不再走这条丢帧路径。

下一份内核打开 `CONFIG_DMABUF_HEAPS_SYSTEM`。版本字符串仍是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2 SMP PREEMPT Sat Oct 31 19:57:12 EDT 2026`。2026-10-31 把这份 FIT 和 super 写入 SanDisk（序列号 `000000002959`）。内核槽读回 sha256 `6f94de3cb39f0537aaedb2d1beac7669c49f36da4881345b21bd1ffe98bee55f`。super 读回 sha256 `bab6e5bf3f432350757f5da8f9ba5af82d3ee9c17dfe97f9e81318daa097b3d7`，大小 `8589934592`。pmOS_boot、metadata、misc、userdata 的开头 1 MiB 没有变。

这次 Ctrl+U：蓝牙耳机正常。USB 耳机连续播放、提示音和耳麦录音正常。触摸反馈音经常播不出来，前面已经有别的声音在播时就能跟上。USB 播放在 standby 时把 PCM 关掉，下一次打开等时传输比一声触摸音更慢，整段点击在声卡出声前就结束了。USB 播放改为 standby 时保持 PCM 打开，用静音把传输留着。内置扬声器和麦克风完全没有声音。`snd-usb-audio` 比平台声卡先注册，内置卡是 card 1，策略仍打开 `CARD_0`。日志是 `parsed with card id 0, device id 5`，然后 `configureKukuiInput: mixer_open failed`，流停在 ERROR。上次调试时内置卡是 card 0，所以同一段 WAV 能出声。HAL 改为按 `mt8183_mt6358` 找卡号，模块也改成先加载平台声卡。这次开机把新 HAL 挂到正在跑的进程上之后，`pcmC1D0p` 处于 RUNNING，`DL1`、`I2S3`、`HiFi Playback` 和 `SD_MODE` 都是 On。内置麦 `hw:1,5` 录到 1 秒，峰值 3277。还没有听感确认。2026-10-31 把上一份 super 写入 SanDisk（序列号 `000000002959`），读回 sha256 `e3ae223c436bc18ab31ea2469883e8d3ebc04b763fbc401d5d8a1d2e44ef5e58`。2026-11-01 按当时的源码又编了一份并写入，读回 sha256 `1325988136bdcb71b82fcff4b8b8534f89c19193f649fd06ad7cb14c16bff965`，大小 `8589934592`。内核槽、pmOS_boot、metadata、misc、userdata 的开头 1 MiB 没有变。还没有这次 Ctrl+U 的结果。写入时共享树里的 Kukui 音频补丁还在；写完之后已经用 `--reverse` 拿掉。

2026-11-01：编译 Kukui 不再检出 `device/google/gru`。传感器 HAL 在本仓库。`local_manifests/kukui.xml` 只列出 LineageOS 的 mainline、mesa、minigbm 这些上游仓库，不拉 Gru 的设备树。这台机器的 `.repo/local_manifests/gru.xml` 已经列了同一批路径，两份一起放会让 `repo sync` 报重复，所以脚本看到 `gru.xml` 就不再拷 `kukui.xml`。`patches/apply-patches.sh` 把 `device/google/kukui` 逐个文件链进 Lineage 树，并打上本仓库的补丁。干净的 `hardware/interfaces` 用 `hardware_interfaces_audio_kukui_standalone.patch`：USB 阻塞读写、麦增益、按卡名找 MT8183、扬声器阻塞写、USB 播放在 standby 时保持打开、A2DP standby。这份不引用 DA7219。这台机器的共享树已经打过 Gru 的音频补丁，脚本会改用 `hardware_interfaces_audio_kukui.patch`；属性不是 `kukui` 时仍走 DA7219。编 Gru 之前如果这份补丁还在，用 `--reverse` 拿掉。另外四份是开机要用、和机型无关的修改：memfd、codec2 在 `IConfigurable` 失败时返回而不是 `CHECK`、mesa 25 的 `board.mk`、v4l2 seccomp 的 `fcntl` 和 `uname`。没有把 Gru 的 rockchip、DA7219、摄像头和 sepolicy 补丁搬过来。`device.mk` 在 `KukuiMixer.h` 不存在时会停掉 Kukui 的编译。共享树现在仍是拿掉 Kukui 音频补丁的状态，下一份编译之前先跑 `patches/apply-patches.sh`。

## 顺序

前一项能用再做下一项。

1. `evdev.ko` 已加载。外接鼠标和键盘盖触控板能用。
2. Panfrost。第十五次启动仍是 Mali-G72 GLES 3.1。
3. Wi-Fi 和无线 adb。第十九次已连上 `"Not 6GHz"`，`10.0.0.104`，无线 adb 可用。
4. 触摸、旋转、USI 笔。手指和笔的方向都已经对。屏幕导航键已打开。加速度计已进 super。postmarketOS 那组矩阵叠在 `ORIENTATION_270` 上多转了 90 度，正放时画面是竖屏。单位矩阵在这次开机里把画面拉回 1920×1200。读数慢是因为关掉的陀螺仪仍以 200 Hz 占着 EC 的 FIFO。2026-10-31 这次 Ctrl+U 已确认：正放是 1920×1200，加速度计大约每 40 毫秒一笔，陀螺仪 ODR 在不用时是 0。读回 sha256 `44e7b35f059e05ee4fd0fe8bf9e8cba52bff0bbb144eb729527183e0d10d2e90`。
5. 底座键盘、触控板，以及拆下底座后的平板模式。热插拔已经能用。2026-11-01 底座插着时，Hammer 键盘是完整键盘（`KeyboardType` 2），同一颗 `18d1:503c` 的另一接口是触控板（`MOUSE | TOUCHPAD`）。Whiskers 的 Tablet Mode Switch 当时是松开的。Android 16 自己看的不是这颗开关，而是「完整键盘和触控板同时在」。两个都在就把内置屏改成桌面优先，少一个就回到全屏。内置屏要先被标成能承载桌面，这条路径才会走。`config_isDesktopModeSupported` 和 `config_canInternalDisplayHostDesktops` 都改成 true。Gru 上打开内置桌面后，最近任务里会多出桌面卡片；那次是无条件打开。这里只在底座的键盘和触控板都在时进入桌面。拔下底座、只接蓝牙键盘，都仍是平板。

顶行按键帽上的图标映射，不留成 F1–F10。从左到右是返回、前进、刷新、全屏、最近任务、亮度减、亮度加、静音、音量减、音量加。亮度键和音量键没有第二套实体键。布局文件一旦匹配 `18d1:503c` 就整份替换 `Generic.kl`，所以其余键仍按通用键盘。搜索键仍是 Meta。布局做不到「搜索键加顶行等于 F 键」。2026-11-01 只把这份 super 写进 SanDisk（序列号 `000000002959`）。大小 `8589934592`。读回 sha256 `517c8f02bc51cb72850873c8992f9c184d453103139db2c9f9632d55667da213`。内核槽开头仍是 `6f94de3cb39f0537aaedb2d1beac7669c49f36da4881345b21bd1ffe98bee55f`。卡未挂载。还没有这次 Ctrl+U。
6. 背光。滑块改的是框架里的亮度，light HAL 也找到了 `backlight_lcd0`（最大 1023）。节点权限是 `root:root` `0644`，HAL 以 `system` 运行，写不进去，所以 sysfs 一直停在设备树默认的 576。`init.kukui.rc` 在 `early-boot` 和 `boot` 时把 `brightness` 交给 `system`。这次开机先 chown 过：0.25 写成 260，0.9 写成 922，然后放回 577。内核那张表是 `0` 到 `1023` 线性插值，不是 Gru 的三次方曲线，没有关 Android 的 gamma。2026-11-01 只把这份 super 写进 SanDisk（序列号 `000000002959`）。大小 `8589934592`。读回 sha256 `a456b6c03b4a42614f360342e23c59d5ecc3c032b64a89e8a11a7c7c54d0ec1b`。内核槽、pmOS_boot、metadata、misc、userdata 的开头 1 MiB 没有变。卡已卸载。还没有这次 Ctrl+U。
7. 蓝牙。QCA6174 走 UART `qca6174-bt`。2026-10-31 这次 Ctrl+U 后蓝牙自己打开，崩溃次数是 0，蓝牙鼠标能用。A2DP 在带上 system heap 的这次启动里耳机播放正常。
8. 扬声器播放，然后是内置麦。Krane sku176 没有 3.5 mm 耳机孔。其它带 TS3A227E 的板有插孔，混音器按 UCM 写了，没在实机上听过。2026-10-31 这次 Ctrl+U：蓝牙耳机正常，USB 连续播放和耳麦录音正常，触摸音在没有别的声音垫着时经常错过。内置扬声器和麦打不开，因为 USB 声卡占了 card 0。HAL 改为按声卡名找 MT8183，USB 播放在 standby 时保持打开。正在跑的进程已换上这份 HAL，`pcmC1D0p` 能进 RUNNING。2026-11-01 再次编译并写入 super，读回 sha256 `1325988136bdcb71b82fcff4b8b8534f89c19193f649fd06ad7cb14c16bff965`。内核槽没动。还没有这次 Ctrl+U 的结果。共享树里的 Kukui 音频补丁在写入后已拿掉。下一份编译用 `patches/apply-patches.sh`，不再需要 `device/google/gru`。
9. 电量和充电。电量计模块已放进 super。9 V 请求要等 EC 固件有对应的主机命令，这一版 `krane_v2.0.2771` 没有。
10. zram。
11. 休眠和唤醒。开关为关时走 `s2idle`，USB 保持供电。2026-10-31 这次 Ctrl+U 已确认：读卡器灯常亮，`suspend_stats` `success=3`，日志有 `PM: suspend entry (s2idle)`，唤醒后仍是同一次启动。每次停留大约 1 秒，EC 计到的睡眠切换是 0。不预先喂看门狗。

## 完成标准

在 4 GB 内存上完成一次「开机、联网、打开网页、安装应用、睡眠、唤醒」。唤醒后仍是同一次启动。网页不是黑的。

## 这一段不做

不写 eMMC，不启用 USB gadget，不把 SELinux 改成 enforcing，不做视频解码、摄像头和 IT6505。不改内核版本字符串。不把 Gru 的触摸和键盘补丁搬过来：那台是 RK3399，输入芯片不同。
