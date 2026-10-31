# 阶段 4：平板日常

2026-10-31 开始。路线图在 [roadmap.md](roadmap.md)。阶段 3 的第十四次 Ctrl+U 已经进入桌面，记录在 [阶段 3](phase-3.md)。这一段仍用内核 `6.18.28-mt81-kukui2`，`#1-kukui-phase2`。不重链内核映像，不改版本字符串，不写 eMMC，不启用 USB gadget，不喂看门狗。镜像保持 vanilla。

## 第十四次启动已经有的

zygote 在内核时间 24.06 秒启动，开机动画在 28.85 秒起来，`sys.boot_completed=1` 在 55.48 秒。SurfaceFlinger 报 Mali-G72 (Panfrost)、OpenGL ES 3.1 Mesa 25.3.3。路线图里「第一帧先用软件渲染，确认加速后再拿掉 SwiftShader」这一步不做：这台机器从阶段 3 起就是 Panfrost，镜像里没有 SwiftShader。

蓝牙 HAL 仍在崩溃。`vendor.bluetooth-default` 在 48.63 秒收到 SIGABRT，`initializationComplete` 的状态不是成功。这台镜像里没有可用的 QCA UART。阶段 3 已经把 `persist.sys.disable_rescue=true` 放进系统属性，这次没有恢复出厂。蓝牙排在输入和 Wi-Fi 后面，现在不修。

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

## 人工测试

U 盘从工作站卸载之后再做。

1. 卸下 U 盘，插到 Krane 上。外接鼠标仍接在 hub 上，键盘盖装上。
2. 重启，开发者屏幕按 Ctrl+U。
3. 桌面应仍停住。手指在玻璃上从上往下划，内容应跟着往下走。若变成镜像，或方向仍不对，告诉我。
4. 打开 Wi-Fi，看能否扫到网络。能连上再试一次。这次还不能算已经可用。
5. 再重启，不要按 Ctrl+U。应回到 eMMC 上的 postmarketOS v26.06。
6. 把 U 盘插回工作站。日志在 `pmOS_boot` 的 `kukui-phase3.log`。

## 顺序

前一项能用再做下一项。

1. `evdev.ko` 已加载。外接鼠标和键盘盖触控板能用。
2. Panfrost。第十五次启动仍是 Mali-G72 GLES 3.1。
3. Wi-Fi，然后是无线 adb。SDIO 卡已枚举。ath10k 模块和 QCA6174 固件已写入 super，等这次 Ctrl+U。有线 adb 仍然不可用。
4. 触摸、旋转、USI 笔。触摸已能点，方向按第十六次的手势写成 `ORIENTATION_270`。笔还没改。
5. 底座键盘、触控板，以及拆下底座后的平板模式。Hammer 已经在 `input3`。Whiskers 的 Tablet Mode Switch 在 `input0`，`cros_ec_buttons` 在 `input1`，都在 1 秒内注册。
6. 背光。
7. 蓝牙。上面的 SIGABRT 留到这一项。
8. 扬声器播放，然后是内置麦和 3.5 mm 耳机孔。
9. 电量和充电。
10. zram。
11. 休眠和唤醒。第十四次在没有输入时大约一分钟灭屏，挂起被拒绝。等输入和显示稳定后再做。不预先喂看门狗。

## 完成标准

在 4 GB 内存上完成一次「开机、联网、打开网页、安装应用、睡眠、唤醒」。唤醒后仍是同一次启动。网页不是黑的。

## 这一段不做

不写 eMMC，不启用 USB gadget，不把 SELinux 改成 enforcing，不做视频解码、摄像头和 IT6505。不改内核版本字符串。不把 Gru 的触摸和键盘补丁搬过来：那台是 RK3399，输入芯片不同。
