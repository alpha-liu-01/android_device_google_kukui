# 细节修复

2026-11-03 开始。阶段 4 的睡眠和 USB 开关记在 [阶段 4](phase-4.md)。这里只记阶段 4 收口之后的单项。没有用户确认之前，不把一项写成已经修好。

## Wi-Fi 睡眠不断开

不另加开关。睡眠时让 Wi-Fi 保持已连接，和蓝牙一样常开。

USB 那个开关是因为系统盘可能就在这颗控制器上，睡眠掉电会结束同一次启动。Wi-Fi 没有这条失败路径。`phy0` 是 ath10k_sdio QCA6174，`iw phy phy0 wowlan show` 列出睡眠唤醒：断开、魔术包、包模式（22 条，1–134 字节）、网络检测。这些都是固件在低功耗里维持关联，主机只在断开或魔术包时被叫醒。`any` 会让射频对每个包都醒，功耗不是同一档，不用。组密钥轮换不在这份能力里，睡得很久、AP 中途换 GTK 时仍可能掉线。那是偶发，不是每次灭屏都断开。

蓝牙不在这项里。用户看到睡眠不会把它断开，控制器自己留着链路。USB 开关保持原样。这次启动 `androidboot.boot_devices=soc/11230000.mmc`，`/sys/devices/platform/soc/11201000.usb/suspend_power_off` 是 1，`/sys/power/mem_sleep` 是 `s2idle [deep]`。系统盘在 eMMC 上，这个 USB 选择不会拆掉正在跑的系统。

2026-11-03 12:05:18 的日志是改之前的一次 `deep`：`PM: suspend entry (deep)` 同一秒 `wlan0: deauthenticating from 34:98:b5:88:a8:a3 by local choice (Reason: 3=DEAUTH_LEAVING)`。当时 `WoWLAN is disabled`。`wpa_supplicant.conf` 只有 `wowlan_disconnect_on_deinit=1`，没有 `wowlan_triggers`。mac80211 在没有 WoWLAN 时进睡眠会自己发这个 deauth。Android 的 wifi 框架和 wificond 都不写这个配置。

配置加上 `wowlan_triggers=disconnect magic_pkt`。模板是 `device/google/kukui/wpa_supplicant.conf`。这台机器正在用的是 `/data/vendor/wifi/wpa/wpa_supplicant.conf`，supplicant 启动时文件已经存在就不会再从 `/vendor/etc/wifi/wpa_supplicant.conf` 覆盖。所以这次直接改了 data 里的那份。改完用 `iw` 先关掉 WoWLAN，再 `svc wifi disable` 然后 enable。起来之后仍连着「Not 6GHz」，地址仍是 `10.0.0.113`，`iw phy phy0 wowlan show` 变成：

```
WoWLAN is enabled:
 * wake up on disconnect
 * wake up on magic packet
```

这次重启 Wi-Fi 自己也会打一条 `DEAUTH_LEAVING`，那是 `svc wifi disable`，不是睡眠。内核时间 2217.97 秒那条就是它。

还没有在这项打开之后进过睡眠。`/sys/class/rtc` 是空的，没有闹钟可以把机器自己叫醒，所以没有从这边写 `mem`。下一次锁屏再亮屏才能看关联还在不在。已发出的 zip 和设备上的 super 仍是旧模板。这台的 data 文件会留着。清空 userdata 之后，当前 super 会抄回没有这一行的模板。

2026-11-03 用户锁屏再亮屏，Wi-Fi 还是重新连上。这不是配置没写上，也不是正常的保持关联。内核时间 2344.19 秒 `PM: suspend entry (deep)`。2344.24 秒 `ath10k_sdio: ignoring unsolicited htc ep0 event`。2347.49 秒 `timed out while waiting for suspend completion`，接着 `failed to start wow: -110`。2347.51 秒 `wlan0: deauthenticating from 34:98:b5:88:a8:a3 by local choice (Reason: 3=DEAUTH_LEAVING)`。随后 `11240000.mmc` 读卡失败，卡重新枚举，`failed to read from address 0x868: -110`。2348.69 秒 `PM: Some devices failed to suspend, or early wake event detected`，2349.15 秒 `PM: suspend exit`。2354.15 秒重新 authenticate / associate，aid 仍是 5。WoWLAN 节点在唤醒后还是 disconnect 和 magic packet。这次睡眠没有停住，驱动在固件 3 秒没回睡眠完成之后把连接拆了，系统把这次 suspend 中止了。

固件 `WLAN.RMH.4.4.1-00174` 里有 `fail to enter wow`。主机只在收到 HTC 消息 6 时才算睡眠完成。这次先到的是一条没被认出来的 ep0 消息，消息号没有打出来。为了看这条消息，把 `ath10k_core` 的 `debug_mask` 设成 6，再写了一次 `/sys/power/state`。之后 `10.0.0.113` 不再应答。调试输出把那次的消息号冲出了内核缓冲。平板唤醒后 `debug_mask` 已改回 0。

2026-11-03 15:31 用户再锁屏并唤醒。电源键睡眠到电源键唤醒间隔 4.6 秒（`mLastSleepTime=2895555`，`mLastWakeTime=2900186`）。前两次 `deep` 在冻结用户空间时中止，358 个任务拒绝冻结。第三次内核时间 2900.10 秒 `PM: suspend entry (deep)`，冻结完成，CPU1 到 CPU7 被 PSCI 关掉，随后立刻重新打开，`crng reseeded on system resumption`，2900.34 秒 `PM: suspend exit`。15:31:30.921 SurfaceFlinger 把显示电源模式设回 2。从挂起控制台到关掉非启动 CPU 只有大约 31 毫秒，没有 `failed to start wow`，也没有 `Some devices failed to suspend`。这次没有 `wlan0: deauthenticating`。15:31:30.973 唤醒时状态已经是 `L2ConnectedState`，15:31:31.248 supplicant 仍把 `34:98:b5:88:a8:a3` 标成 associated。同一 BSSID「Not 6GHz」，地址仍是 `10.0.0.113`。`setSuspendModeEnabled` 在唤醒时返回失败，连接没有因此拆掉。CPU 关掉之后没有在睡眠里停留，唤醒请求已经在入口等着。

## ReSukiSU

可以。这棵内核是 6.18.28，不是 GKI。Tracepoint 挂钩只给 GKI 2，这里不能用。SuSFS 没有移植，不开。用手动挂钩，源固定在 BakaSU `v4.2.0-rc3`（`239e1e88`，4471 个提交）。版本号按他们的算法是 `30000 + 4471 + 700 = 35171`，和官方 arm64 管理器 `com.resukisu.resukisu` 的 versionCode 一致。管理器必须保持原签名。用 ROM 证书重签之后，内核会拒绝它。

6.8 以后不能再用 LSM 自动挂钩 setuid 和 init rc。`CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK` 和 `CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK` 关掉，改在 `kernel/sys.c` 的 `__sys_setresuid` 和 `fs/read_write.c` 的 `read` 里调用。另外按文档挂了 `do_execveat_common`、`faccessat`、`newfstatat`、`fstatat64`、`newfstat`、`fstat64`、`reboot`。音量减的自动 input handler 留着。`KALLSYMS_ALL` 本来就是打开的。`CONFIG_MODVERSIONS` 没开，`UTS_RELEASE` 仍是 `6.18.28-mt81-kukui2`，已有模块的 vermagic 没变。

「更新系统」会写三样：U 盘上的 super、`android.kpart` 写到名字是 `android_kernel` 的分区、`menu.kpart` 写到 `menu_kernel`。它不写 U 盘自己启动用的 `kernel.kpart`。所以 eMMC 上的 Android 内核可以跟系统一起换。菜单内核也会被重写，但它不需要 ReSukiSU，可以继续用原来的 `menu.kpart`。`android_kernel` 分区是 32 MiB，新的 `android.kpart` 是 12488704 字节。

2026-11-03 内核编过。`Image` 在 `work/phase2/linux-6.18.28/arch/arm64/boot/Image`。内核里的版本字符串是 `v4.2.0-rc3-239e1e88@ReSukiSU`。用原来那份 `android.kpart` 的 ramdisk、dtb 和命令行，只换了内核，打到 `work/resukisu/android.kpart`，sha256 `1998cc6475f44654ba19e47532822d336083bce4499554c9d589bbf93754ceed`。命令行仍有 `androidboot.boot_devices=soc/11230000.mmc`。没有写 U 盘，没有写 eMMC，没有重启。

管理器是官方 `ReSukiSU_v4.2.0-rc3_35171-arm64-v8a-release.apk`，sha256 `25657bc449439687608fffa04b4b586de90fc405e3dc6217bd997fc71ba0a0a1`。`device.mk` 把它作为 `ReSukiSU` 收进 system_ext。包是预签名，dex 和 JNI 都是压缩的，所以 Android.bp 用 `presigned`、`preprocessed` 和 `skip_preprocessed_apk_checks`，不放进 priv-app。清单里还有可选的 `androidx.window.extensions` 和 `androidx.window.sidecar`，这两项写在 `optional_uses_libs`。Soong 读到的 apk 必须是普通文件。第一次编出来的 system_ext 里，`ReSukiSU.apk` 是一条 133 字节的符号链接，指向编译机路径。改成普通文件之后再编，`system_ext.img` 里是 9379362 字节的普通文件。

新的 super 展开后是 `work/resukisu/super.raw`，正好 8589934592 字节，sha256 `a3b991c9a19efc9fbef43af86a9fe83ecb8e1b4891fae624551a9365e8fdc945`。它来自当前树的一次 `m superimage`，不是在 `super.bigcore.raw` 上打补丁。内核模块没有重编，vermagic 仍是 `6.18.28-mt81-kukui2 SMP preempt mod_unload aarch64`。没有写 U 盘，没有写 eMMC，没有重启。还没有启动过这份内核，不能说 root 已经可用。
