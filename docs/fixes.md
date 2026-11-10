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

新的 super 展开后是 `work/resukisu/super.raw`，正好 8589934592 字节，sha256 `a3b991c9a19efc9fbef43af86a9fe83ecb8e1b4891fae624551a9365e8fdc945`。它来自当前树的一次 `m superimage`，不是在 `super.bigcore.raw` 上打补丁。内核模块没有重编，vermagic 仍是 `6.18.28-mt81-kukui2 SMP preempt mod_unload aarch64`。2026-11-03 17:02 写入序列号 `20120501030900000` 的安装盘 `/dev/sdb`。super 写到 `sdb3`，读回 sha256 `a3b991c9a19efc9fbef43af86a9fe83ecb8e1b4891fae624551a9365e8fdc945`。`pmOS_boot` 上的 `kukui-install/android.kpart` 换成新文件，读回 sha256 `1998cc6475f44654ba19e47532822d336083bce4499554c9d589bbf93754ceed`。`menu.kpart` 仍是 `bc28358a4f965cc4f1cf0da1ff84d42814cacabdd2dff4d8509b5822945b84a6`。U 盘自己的内核槽没有写。没有写 eMMC，没有重启。还没有启动过这份内核，不能说 root 已经可用。

2026-11-03 17:19 平板从 U 盘启动，正在把系统写入 eMMC。`ro.boot.boot_devices=soc/11201000.usb/11200000.usb`。这次启动的 `/data/vendor/wifi/wpa/wpa_supplicant.conf` 只有 `wowlan_disconnect_on_deinit=1`，没有 `wowlan_triggers`。`/vendor/etc/wifi/wpa_supplicant.conf` 已经有 `wowlan_triggers=disconnect magic_pkt`。supplicant 在 data 文件已经存在时不会用模板覆盖。U 盘自己的 userdata 是以前生成的那份，和 eMMC 上改过的 data 文件不是同一个。这次更新不格式化 userdata。锁屏修复在这次 U 盘启动里不生效是预期情况。

ReSukiSU 闪退不是预期。崩溃是 `UnsatisfiedLinkError: library "libkernelsu.so" not found`，发生在进内核之前。包在 `/system_ext/app/ReSukiSU/ReSukiSU.apk`，9379362 字节，清单 `extractNativeLibs=true`，旁边没有 `lib/arm64`。预签名导入不会把 apk 里的 JNI 解出来安装。正在写入 eMMC 的就是这份镜像，写完后打开管理器仍会同样闪退。U 盘启动用的内核槽也没有 ReSukiSU，那是另一件事，不是这次闪退的原因。

库已从官方 apk 解出，复制到 `system_ext/app/ReSukiSU/lib/arm64/`。新 super 展开后仍是 8589934592 字节，sha256 `2250044b06359bb534f0d079e6cb601d0b23b22e5c723d63bead76d83404adce`，在 `work/resukisu/super.raw`。`system_ext.img` 里 `libkernelsu.so` 是 18704 字节的普通文件。这次 eMMC 写入还在用 U 盘上的旧 super，没有改那张盘。

2026-11-03 17:39 新 super 写入序列号 `20120501030900000` 的 `/dev/sdb` 分区 `sdb3`。读回 sha256 `2250044b06359bb534f0d079e6cb601d0b23b22e5c723d63bead76d83404adce`。`android.kpart`、`menu.kpart` 和 U 盘自己的内核槽没有再写。没有写 eMMC。

2026-11-03 18:00 eMMC 启动，`ro.boot.boot_devices=soc/11230000.mmc`。内核日志有 KernelSU 35171，工作模式 Built-in。管理器能打开，界面仍是「未安装」，点下去要修补 `init_boot`。这台没有 `init_boot`，那个按钮不能按。

两条界面现象是同一条失败。`KsuCli` 18:00:24 执行 `/system_ext/app/ReSukiSU/lib/arm64/libksud.so` 返回 error 13，接着 `Unable to create a shell!`。这个文件在 erofs 里是 0644。管理器要把 `libksud.so` 当程序执行，权限不够。没有这个 shell 时，`getDefaultPartition()` 在内核版本大于 5 的机器上把默认分区写成 `init_boot`。签名检查也走这个 shell：`ksud debug get-sign` 拿不到输出，就显示「您使用的管理器并非 ReSukiSU 官方管理器」。apk 本身是官方包，签名长度 `0x377`，哈希 `d3469712b6214462764a1d8d3e5cbe1d6819a0b629791b9f4101867821f1df64`，和内核 `EXPECTED_HASH_RESUKISU`、管理器源码里的官方值一致。横幅不是签错了包。

只改权限也不够。`Natives.isManager` 为假时，版本号被写成空，6.18 会被 `isGKI()` 判成「未安装」。内核只在 `/data/app` 里找 `base.apk`。系统里的路径是 `/system_ext/app/ReSukiSU/ReSukiSU.apk`，`get_pkg_from_apk_path` 解析不了，所以没有 `Crowning manager`。`handle_setresuid` 到 uid 10148 只说明 setuid 挂钩看见了这个进程，不代表它被登记成管理器。

`device/google/kukui/config.fs` 把 `system_ext/app/ReSukiSU/lib/arm64/libksud.so` 设成 0755。`BoardConfig.mk` 把它加进 `TARGET_FS_CONFIG_GEN`。编出来的 `system_ext.img` 里这个文件是 `0755/rwxr-xr-x`，5679064 字节；`libkernelsu.so` 仍是 0644。apk 仍是 9379362 字节的普通文件。

内核在 `throne_tracker.c` 增加 `crown_system_manager`。扫完 `/data/app` 之后，再对 `/system_ext/app/ReSukiSU/ReSukiSU.apk` 做原来的 v2 签名检查，包名对上 `packages.list` 里的 `com.resukisu.resukisu` 才登记。补丁是 `bringup/kernel/0002-resukisu-system-manager.patch`。版本字符串仍是 `v4.2.0-rc3-239e1e88@ReSukiSU`，版本号仍是 35171。新 `android.kpart` 12484608 字节，sha256 `514c836321c71dfd5d139cff7ad8d9e202a34eebda11263e0648f597f07ffd85`，命令行仍是 `androidboot.boot_devices=soc/11230000.mmc`。

新 super 展开后 `work/resukisu/super.raw`，正好 8589934592 字节，sha256 `85f8afaeaec11d74c2351aa7b307583f4f1c7146240dab1b44508659c79bda1f`。上一份 `2250044b06359bb534f0d079e6cb601d0b23b22e5c723d63bead76d83404adce` 已经在 eMMC 上。管理器要等这份 super 和这份 `android.kpart` 一起通过「更新系统」写上去之后才能看。还不能说 root 已经可用。

2026-11-03 18:25 这两份写入序列号 `20120501030900000` 的 `/dev/sdb`。super 写到 `sdb3`，读回 sha256 `85f8afaeaec11d74c2351aa7b307583f4f1c7146240dab1b44508659c79bda1f`。`pmOS_boot` 上的 `kukui-install/android.kpart` 读回 sha256 `514c836321c71dfd5d139cff7ad8d9e202a34eebda11263e0648f597f07ffd85`，命令行仍是 `androidboot.boot_devices=soc/11230000.mmc`。`menu.kpart` 仍是 `bc28358a4f965cc4f1cf0da1ff84d42814cacabdd2dff4d8509b5822945b84a6`。U 盘自己的内核槽写前写后都是 `2c52f071bdd707b2078e1e30aeb344b645a3a64f51e7e9d233e53f50f64a5512`。没有写 eMMC，没有重启。

2026-11-03 19:08 这次 eMMC 启动大约 29 分钟时，三项调试还在跑。`kukui-logcat` 的 shell（pid 3727）往 `/dev/kmsg` 写，内核态 54 秒；另一个 `logcat` 把 `/data/kukui-logcat.txt` 轮转，盘上约 13 MiB。`kukui-keep` 的两个子进程还在，pid 1625 开着 `/kukui-phase3.log`。`mmcblk0p2` 已有 3716 次写。`vtcon0` 仍绑定，命令行是 `loglevel=7` 和 `printk.devkmsg=on`。过滤名单里没有 audit 或 AVC。

这三项已从下一份镜像拿掉。`kukui-logcat.sh` 删除，`init.kukui.rc` 不再启动它。`kukui-keep` 仍等待 `pmOS_boot` 和 `super` 出现，然后执行 Android init，并保留 Wi-Fi 重试；不再挂日志分区，不再留读 kmsg 和 `fsync` 的子进程。eMMC 命令行改为 `loglevel=4`，去掉 `printk.devkmsg=on`。`androidboot.selinux=permissive` 还在。内核 lzma 的 crc32 仍是 `2aa7b1b9`，ReSukiSU 那份内核没有重编。

新 super 展开后 `work/resukisu/super.raw`，8589934592 字节，sha256 `9af6829df5b902e9dd41df8c93813d2a12423535b8c80730492ba4d68593c4a1`。`vendor.img` 里没有 `bin/kukui-logcat.sh`。新 `android.kpart` 12500992 字节，sha256 `b57b401b133fd6015081336b037cf4a19a60c76bddc556eebc44e2f72272fbca`。ramdisk 里的 `/init` 有 `kukui-android phase3 emmc`，没有 `kukui-phase3.log`。命令行是 `loglevel=4`，`androidboot.boot_devices=soc/11230000.mmc`，没有 `printk.devkmsg`。没有写 U 盘，没有写 eMMC。上一份还在机器上，这次启动里的日志进程要等「更新系统」写上这两份并重新开机才会消失。

2026-11-03 19:38 这两份写入序列号 `20120501030900000` 的 `/dev/sdb`。super 写到 `sdb3`，读回 sha256 `9af6829df5b902e9dd41df8c93813d2a12423535b8c80730492ba4d68593c4a1`。`pmOS_boot` 上的 `kukui-install/android.kpart` 读回 sha256 `b57b401b133fd6015081336b037cf4a19a60c76bddc556eebc44e2f72272fbca`。命令行是 `loglevel=4`，`androidboot.boot_devices=soc/11230000.mmc`，没有 `printk.devkmsg`。`menu.kpart` 仍是 `bc28358a4f965cc4f1cf0da1ff84d42814cacabdd2dff4d8509b5822945b84a6`。U 盘自己的内核槽写前写后都是 `2c52f071bdd707b2078e1e30aeb344b645a3a64f51e7e9d233e53f50f64a5512`。没有写 eMMC，没有重启。

2026-11-03 20:05 按上次 Rufus 整盘包的方式打了 `work/release/lineage-23.2-kukui-20261103b.zip`，1110373465 字节，sha256 `d07a61517a02efc316108c3ad0aefc2404a11c77bd3db4e23983ab419a0542f8`。当天已发出的 `lineage-23.2-kukui-20261103.zip` 没有覆盖。包里的 super 是 `9af6829d…`，`android.kpart` 是 `b57b401b…`。U 盘启动内核是同一份内核 lzma，命令行改为 USB 和 `loglevel=4`，sha256 `6f91284270a41eae5e21707140d5545756420222edcdef9d21c03542e84f687a`。没有写盘，没有用 Rufus 试过。

2026-11-04 02:22 用户说全新安装会提示 Android 内核不在 U 盘上，更新系统则正常。安装器的 `check_payload` 在「只装 Android」和「Android 和 Linux」里要求 `/kukui-install/android/Image`。`lineage-23.2-kukui-20261103b.img` 的 `pmOS_boot` 里只有 `android.kpart` 和 `menu.kpart`。当前菜单不读那份 Image。本机安装盘是后来补写的，旧的 `android/Image` 还在，所以这里复现不了。

2026-11-04 02:37 安装器改为只认 kpart。只装 Android 核对 `android.kpart` 含 `soc/11230000.mmc` 且不含 `11201000.usb`。Android 和 Linux 再核对 `menu.kpart` 含 `console=ttynull`，并要求 eMMC 的 `pmOS_kernel`、`pmOS_boot`、`pmOS_root` 起点是 8192、73728、1122304，`pmOS_boot` 是 ext4。不再拷贝 Image、cmdline 或 initrd。`bootmenu` 格式化成空的 ext4。工作站上用假的分区名跑过这两项检查：名字不对报 `not_pmos_layout`，启动分区不是 ext4 报 `linux_boot_not_ext4`，没有 `android/Image` 时 kpart 检查通过。没有在平板上安装。

新 super 展开后 8589934592 字节，sha256 `20b27983225fc857edbfd5c63cd777d14307c72da654f6661c598c5eea13f10c`。展开后的 super 里能搜到 `require_linux_layout`。zip 是 `work/release/lineage-23.2-kukui-20261104.zip`，1110366362 字节，sha256 `f4c20440484d27ed05a8ca577f44c7a13ba32918e11eeaf01b9083ec0c985a7e`。内核三份和 `20261103b` 相同。没有写盘。

2026-11-04 21:07 用户指出官方 postmarketOS 的 boot 是 ext2。这台 eMMC 上 `mmcblk0p2` 的 `PARTNAME` 是 `pmOS_boot`，起点 73728，`blkid` 是 ext2；`pmOS_kernel` 起点 8192，`pmOS_root` 起点 1122304，根是 40 GiB 的 ext4。上一份安装器在这里报 `linux_boot_not_ext4`。菜单挂载时指定的类型是 ext4，而且是只读。内核配置是 `CONFIG_EXT4_FS=y`、`CONFIG_EXT4_USE_FOR_EXT2=y`，只读挂载不要求 journal，所以 ext2 能挂上。安装器改为接受 ext2、ext3、ext4。工作站上假分区测试：ext2 通过，vfat 拒绝。

新 super 8589934592 字节，sha256 `360a0f6b092e7d0070d9c52360448770eed1d88dcc47a0b195dd4825dabb84c2`。super 里的 vendor 分区和编出来的 `vendor.img` 逐字节相同，里面有 “Official postmarketOS formats … as ext2”。zip 是 `work/release/lineage-23.2-kukui-20261104b.zip`，1110373933 字节，sha256 `3daed0fad2897913310b5723227764a81619923831b87cd168bc1d7130893437`。没有写盘。

2026-11-04 21:25 用户说解锁图案和密码无法设置，只有「无」和「滑动」。`ChooseLockGenericController` 在 `hasSecureLockScreen()` 为假时隐藏图案、PIN 和密码。`LockSettingsService` 用系统功能 `android.software.secure_lock_screen` 决定这个值。当前 product 的 system 和 vendor 权限目录里没有这份声明。软件 Gatekeeper 已经在镜像里。`device.mk` 增加 `android.software.secure_lock_screen.xml`。

新 super 8589934592 字节，sha256 `a4d0f147010a4406ec36e88dfc74e2b8240269897eb0b4183c4f32db432ae0ba`。vendor 分区和 `vendor.img` 一致，里面能搜到 `android.software.secure_lock_screen`。zip 是 `work/release/lineage-23.2-kukui-20261104c.zip`，1110377750 字节，sha256 `7667a5978f6cbd6bcbdd85eb0e17e7443d1322d66e6490d01d10a6366420316f`。没有写盘，也没有在平板上设过密码。

2026-11-05 用户说只装 Android 在内置盘仍是 ChromeOS、没装过 postmarketOS 时会显示 “Could not back up the kernel slot.”。这条路径在抹掉分区表之前，把 `mmcblk0p1` 整份复制到 U 盘 512 MiB 的 `pmOS_boot`。ChromeOS 的第一分区是 STATE，远大于这块空间，复制写满就失败。只装 Android 实际要的是：U 盘上的 `android.kpart` 含 `soc/11230000.mmc` 且不含 `11201000.usb`，eMMC 能放下 8 GiB 的 super 和 userdata，并且 eMMC 上没有已挂载的分区。它不看分区名，也不要求 ext2 或 ext4。

备份改为始终保存 GPT。第一分区只在 1 到 65536 扇区（最多 32 MiB，也就是内核槽）时才复制。更大、为 0、读不到或不是数字时跳过，然后继续抹盘。扇区数超过五位时先按位数跳过，避免 toybox 的 32 位有符号比较溢出。工作站上 65536 扇区会复制，65537、268435456 和 0 会跳过。`sh -n` 通过。

三个模式各加了一个不写盘的检查。只装 Android 做上面的检查，并说明会不会备份第一分区。Android 和 Linux 仍要求现有的 postmarketOS 布局，并对根分区做 `e2fsck -n`，退出码不大于 4 算通过。更新系统只做原来的布局检查。界面下方增加安装器日志。只装 Android 的确认文案改为 eMMC 上的内容会被删掉。

新 super 8589934592 字节，sha256 `2d138070f0370c8f589b1b49ec4f4c8103e45c1cfa001b0df8e49dd8bdaaf0ea`。展开后的 vendor 分区和 `vendor.img` 逐字节相同，解出来的 `kukui-installd` 含有 “not a 32 MiB kernel slot” 和 `state=dry_ok`。`KukuiInstall.apk` 里有 “Check Android only” 和 “检查仅安装 Android”。zip 是 `work/release/lineage-23.2-kukui-20261105.zip`，1110350719 字节，sha256 `d95aac1a88439325667ea047e4512c231b709a5acbe3ffab9e368e09a8598ce9`。内核三份和 `20261104c` 相同。没有写盘，也没有在 ChromeOS 盘上跑过这条路径。

2026-11-08 合上键盘盖不睡眠，打开可以亮屏。`cros_ec_buttons` 的 `SW_LID` 就是这只盖。开盖会走 `wakeUpFromLid`。合盖要 `Settings.Global.lid_behavior=1` 才调用 `goToSleep`，这台原来是 0。`config_lidControlsSleep` 默认 false，框架只在设置第一次建立时把它抄进 `lid_behavior`。overlay 改为 true。`kukui-lid.sh` 在开机完成后，如果 `/data/system/kukui_lid_behavior` 还不存在，就把 `lid_behavior` 写成 1 并留下这个文件，避免每次开机覆盖以后的修改。

这次没有换镜像。正在跑的系统上直接写成 1 之后，`dumpsys window policy` 是 `LID_BEHAVIOR_SLEEP`。用户确认合盖睡眠、开盖唤醒。启动设备是 `soc/11230000.mmc`，同一次启动的运行时间大约 96189 秒。`mem_sleep` 当时是 `s2idle [deep]`。00:36:32 和 00:36:49 两次合盖都是 `reason=lid_switch`、`lidState=0`，内核记录 `PM: suspend entry (deep)`。第一次在进入后马上退出并再次进入，00:36:38 开盖唤醒。第二次保持到 00:37:23 开盖，`WAKE_REASON_LID`，`PM: suspend exit`，亮屏 361 毫秒。`suspend-service` 读不到 wakeup reason，resume 有 `rpm_suspend` 警告，唤醒没有被拦住。整次启动的 `suspend_stats` 当时是 `success=7`、`fail=10`，失败步骤都是 freeze，`errno=-16`。内核 `dmesg` 环形缓冲停在启动后 1539 秒，这两次只在 logcat 里。下一份镜像还没编。

2026-11-08 USB 睡眠供电从桌面应用改成设置里的开关。`KukuiUsbSuspend` 仍是 Kukui 的 `system_ext` 特权应用，其它机型的 `device.mk` 不包含它。原来的 `com.android.settings.action.SETTINGS` 只在 `com.android.settings` 包内查找，所以那一行从来不会出现。现在由 `UsbSuspendSettings` 用 `com.android.settings.action.IA_SETTINGS` 注入「系统」页，类别是 `com.android.settings.category.ia.system`。这一行本身是开关，点文字打开原来的说明页。桌面图标去掉。说明页有自己的返回栏，内容在系统栏之内再留 24dp。节点和 `/data/system/kukui_usb_suspend_power_off` 的读写没变。`KukuiUsbSuspend` 单独编过。正在跑的系统用 `adb install` 装成了更新，没有重启。设置的「系统」页底部有「USB 睡眠供电」，摘要是「睡眠时是否断开 USB 供电」，开关是开的，和节点里的 `1` 一致。点这一行会打开说明页，内容离系统栏和屏幕边缘留有空隙，返回键在标题栏上。分区里的旧 apk 还在，这份更新在 `/data/app`。下一份镜像还没编，清掉数据之后会回到分区里的旧应用。

2026-11-08 按当前提交重编了镜像和刷机包。`apply-patches.sh` 在 `system/cros-codecs` 停下，这份和 `v4l2r`、`v4l2_codec2` 都对不上，没有 `--reverse`，也没有重新生成补丁。音频 overlay、合盖和设置开关需要的其它补丁已经在树上。`m superimage` 成功。

内核补丁 `mt8183-usb-suspend-power.patch` 里有四段 `@@` 行数和正文不一致，`patch` 报 malformed。只改了这几段行数，正文没变。打上之后，睡眠断电时不再打开 USB 唤醒。`Image` 用 clang 21.1.8 编，版本字符串仍是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2`。三份 FIT 换了这份内核，sku176 和 sku0 都在，DTB crc32 仍是 `756e2f96` 和 `2f0c4c74`。内核 lzma crc32 是 `dcd6734c`。U 盘命令行是 `soc/11201000.usb/11200000.usb`，eMMC 是 `soc/11230000.mmc`，菜单是 `console=ttynull`。`kernel.kpart` 和 `android.kpart` 都是 12566528 字节，sha256 `34631f42…` 和 `7f306da1…`。`menu.kpart` 10428416 字节，sha256 `84ee6ef6…`。

super 展开后正好 8589934592 字节，sha256 `7dadaeacb1887953830d37dbff7da4483eaf2e1c8bae9c7c1f4c165ec1c5f33d`。vendor 里有 `kukui-lid.sh`，overlay 里 `config_lidControlsSleep` 是 true。`system_ext` 里的 `KukuiUsbSuspend.apk` 有 `UsbSuspendSettings` 和 `com.android.settings.action.IA_SETTINGS`。

zip 是 `work/release/lineage-23.2-kukui-20261108d.zip`，1110384099 字节，sha256 `d62f83cb7968d8be9733060323808afcead87ff9ac17b65342fb4af076f717d4`。里面只有一份 deflate 的 `lineage-23.2-kukui-20261108d.img`，11756634112 字节。`20261103` 到 `20261108c` 没有覆盖。没有写盘，没有重启。补丁行数那次修改还没提交。

2026-11-08 用户从 U 盘能进 Android。从内置盘进到选择系统的画面时只有背光，没有 Android 和 Linux 两个选项。仓库里的 `kukui-menu.c` 和能显示选项的那份 ramdisk 是同一份。对照 `menu.kpart`：能显示选项的那份（`bc28358a…`，`20261108c` 里的菜单也是同一颗内核）内核 lzma crc32 是 `f3ea1c10`，版本字符串时间是 2026-10-31 19:57:12。`20261108d` 的菜单把这颗内核换成了当天的 `Image`，lzma crc32 `dcd6734c`。ramdisk crc32 仍是 `885a60c2`，sku176 DTB crc32 仍是 `756e2f96`，命令行仍是 `console=ttynull`，没有 `drm_client_lib.active=none`。菜单在画选项之前就把背光写成 700。内核起不来 framebuffer，或者在画之前停住，看起来就是只有背光。`drm_setmaster_ioctl` 里接手 master 的改动从 10 月 31 日就在这棵内核里，能显示选项的那颗和 `20261108d` 的菜单内核都有，不是这次两边对不上的地方。菜单不需要 ReSukiSU，也不需要 USB 睡眠断电那次改动。

`20261108e` 只把菜单内核换回 `f3ea1c10`，并保留 sku0。U 盘内核仍是 `34631f42…`，eMMC 的 Android 内核仍是 `7f306da1…`，super 仍是 `7dadaeac…`。新的 `menu.kpart` 10448896 字节，sha256 `ee69fa15531cdcf08786d4ab0763abdb3a2b5876c9d436ba9fc75d9817a344ca`。zip 是 `work/release/lineage-23.2-kukui-20261108e.zip`，1110404158 字节，sha256 `42b8623aa7ee9fe62ecf426c300e52650121fa8192b52db4687536f05050746a`。`20261108d` 没有覆盖。没有写盘，没有重启。还没有从内置盘看过这个菜单。

2026-11-08 用户确认内置盘菜单可以显示选项。同一份 FIT 再加入 Kodama sku16。设备树从这棵 6.18.28 编译，`compatible` 是 `google,kodama-sku16 google,kodama mediatek,mt8183`，面板是 `auo,b101uan08.3`，64487 字节。三份 FIT 都是五块镜像：内核、Krane sku176、Krane sku0、Kodama sku16、ramdisk。默认配置仍是 sku176。U 盘和 eMMC 的 Android 内核 lzma crc32 仍是 `dcd6734c`，菜单内核仍是 `f3ea1c10`。sku176 crc32 仍是 `756e2f96`，sku0 仍是 `2f0c4c74`。Kodama crc32 是 `0d87a230`。菜单命令行仍是 `console=ttynull`，没有 `drm_client_lib.active=none`。super 仍是 `7dadaeac…`。

`kernel.kpart` 12632064 字节，sha256 `029824c8ca1d9ee72d4e0b5de793ba57b3a35fc3620fba827dd720d345eb1edd`。`android.kpart` 同样大小，sha256 `6d014050f324a7477517f5f55ad3a8ec5a48df39dae8768610a9be4bda313a05`。`menu.kpart` 10514432 字节，sha256 `653bb1a80043f3dd11f97d4059fc5f52335a50a99e8bf3ca4b8a8c0791d0a7ff`。zip 是 `work/release/lineage-23.2-kukui-20261108f.zip`，1110436980 字节，sha256 `e7e5e83a8e83888ab568667767d0ef966a0ce1d6be281c1b03187850fbd32dfc`。`20261108d` 和 `20261108e` 没有覆盖。没有写盘，没有重启。这份包含 Kodama 的包还没有在 10e 上启动过。

2026-11-08 用户装上 `20261108f` 之后硬件解码没有了。解码服务以 `media`（uid 1013）运行，组里当时没有 `camera`。`ueventd.kukui.rc` 把 `/dev/video*`、`/dev/media*`、`/dev/v4l-subdev*` 设成 `0660 system camera`，`media` 打不开 `/dev/video2`。`su 1013` 得到 Permission denied。服务日志是 `No devices supporting H264`，然后走有状态路径并 `Failed to create V4L2 decoder for H264`。这三行是 2026-11-01 的 `f045ada`。`aca6fe4`、`6c5e5e0`、`d676523` 没有改这三行。

同一棵 Lineage 树上，`system/cros-codecs`、`external/rust/crates/v4l2r`、`external/v4l2_codec2` 正向和反向都打不上。工作区是对不上补丁的混合状态。`20261108f` 的 super 是从这棵混合树编的。`libcros_codecs_ffi` 把捕获格式 `MM21`（`0x31324d4d`）原样交给 HAL，HAL 只接受 NV12，报 `Unsupported output fourcc`，然后 `reportError(14)`。

这三份补丁对干净的 25Q4 快照可以正向打上。已把三棵仓库里对不上的未提交改动丢掉，按现有补丁重新打上。没有用 `git diff` 重新生成这三份补丁，也没有 `--reverse`。`apply-patches.sh` 现在对这三份以及其余补丁都是 already applied，退出码 0。`ueventd.kukui.rc` 改回 `0660 media camera`，相机进程仍在 `camera` 组里。解码服务的 rc 按补丁是 `group camera mediadrm drmrpc`。这次 `ueventd` 的修改还没提交。

正在跑的系统上，节点改成 `media:camera`，三份库从 `/data/local/tmp/kukui-codec` bind 到 `/vendor/lib64`，只重启了 `android-hardware-media-c2-v4l2-hal`。SELinux 拒绝了 `shell_data_file`，当前是 permissive。MX Player 播放一部 1080p 的 mp4 时，解码器打开 `/dev/video2`，格式变化的 fourcc 是 `0x3231564e`（NV12），输出布局 Y stride 1920、UV offset 2088960。之后几秒没有 `reportError`。没有重启。bind 和这次改过的节点权限在重启后会消失。用户还没有确认画面。

新 super 8589934592 字节，sha256 `a1789cf2165941fd534594e2425f821140dc91e5f6387f76b93096c972063f52`。vendor 里有 `0660 media camera` 和 `group camera mediadrm drmrpc`。三份 kpart 与 `20261108f` 相同。zip 是 `work/release/lineage-23.2-kukui-20261108g.zip`，1110465701 字节，sha256 `165cb01c56b8cf01e53e08fb4869c2ae23f59405d9724c821fe059d9632dbeec`。里面只有一份 deflate 的 `lineage-23.2-kukui-20261108g.img`，11756634112 字节。`20261108f` 没有覆盖。没有写盘。

2026-11-09 内核换成 Linux 6.18.62（kernel.org 稳定版，tarball sha256 `490a7aedf1b355c565d3a6c05333ccccb5da82064eca46b590448a7099d7d651`）。pmOS mt81 的补丁和配置原本是给 6.18.28 的，在 6.18.62 上只有行号偏移和 fuzz。`bringup/kernel/` 和 `bringup/camera/` 里的补丁，包括 `mtk-mdp3-mt8183-scp-abi.patch`，以及 ReSukiSU 的钩子，都不用改就能打上。clang 18.1.3 编译，没有警告。和 6.18.28 的 `.config` 相比，只多了稳定版新加的选项：`ARM64_ERRATUM_3821522`、`ARM64_ERRATUM_4118414`、`ARM64_WORKAROUND_BROKEN_AMU_CONSTCNT`、`CRYPTO_KRB5`（模块）和 EROFS 的 LZMA 流数。

版本字符串是 `6.18.62-mt81-kukui2`。`modules/` 的 64 个和 `prebuilt/` 的 55 个模块都换成同一次编译的产物，`prebuilt/6.18.28-mt81-kukui2` 改名为 `prebuilt/6.18.62-mt81-kukui2`。每个模块的依赖和旧的一样，`modules.dep`、`modules.load` 不用改。版本字符串写死的地方一起改了：`kukui-keep.c`、`kukui-menu.c`、`wrap-ramdisk.sh`、`pack-install-fits.sh`。换之前，eMMC 内核 FIT 的第一阶段 ramdisk 里装的还是 10 月 30 日 clang 21 编的模块，内核却是 11 月 9 日 clang 18 编的。没有 `MODVERSIONS`，所以能加载，`/proc/config.gz` 也是那个旧 `configs.ko` 里的配置。现在内核、ramdisk 模块和 vendor_dlkm 模块是同一次编译。

sku176 和 sku0 的 DTB 带相机节点，除 phandle 外和之前的内容相同。U 盘 `kernel.kpart` 是 `1c300499…`，eMMC `android.kpart` 是 `f10afc435c840c407b76569576cdeee93dc81024e73f0347b5a82a35cbdd95ec`，super 是 `3d13f03375dcd25fa67db34d67c036f200ab97d039d11a5815a6d84410ec6c52`。`menu.kpart` 仍是 `d7f1cf67…`，里面是它自己的旧内核和旧模块，原因见上面 11 月 8 日菜单只有背光那一段。

先从 U 盘启动 6.18.62，和同一天 6.18.28 在 eMMC 上的记录对比，再用"更新系统"写入 eMMC。eMMC 启动后内核槽和 super 的 sha256 与 U 盘上的镜像一致，userdata 保留。两个内核上：119 个模块全部加载，集合相同；`mtk-svs` 绑定；GPU 和 CCI 的 devfreq、10 个温度区相同。一次 s2idle 的结果也相同：第一次冻结被打断（6.18.62 上 304 个任务，`-16`），第二次成功，大约 0.2 秒后退出，唤醒后 Wi-Fi 重新连上。内核警告的位置相同，都是相机传感器唤醒后再下电一次：`camtg2_sel already disabled`，以及 `vcn18`、`vcamd` 的 `unbalanced disables`。6.18.62 这次另有一条 `EC detected sleep transition timeout`，10 月 31 日 6.18.28 从 U 盘启动时也出现过（见 phase-4.md），`cros_ec.c` 两个版本相同。

Glimpse 播 1080p60 H.264（Big Buck Bunny），每次 20 秒，开 MDP3 时 61.7 到 61.9 fps，大约 1237 帧丢 0 到 1 帧，Codec2 服务 CPU 5.3 秒，MDP3 每帧 7.03 到 7.05 ms。关 MDP3 时 61.7 fps，CPU 10.1 秒。数字和 6.18.28 一样。蓝牙打开后 QCA 固件经 UART 加载，适配器起来。电池的 `time_to_empty_now` 读出来是 EIO；`sbs-battery.c` 在这段稳定版里的两处改动不碰这个读取，6.18.28 上还没对照过。相机拍照、扬声器出声、deep 睡眠和合盖这次没有测。

## 夜间模式在画面动起来时失效（待查）

2026-11-09 记下，没有修。打开夜间模式（色温 2850 K）后，画面静止时是暖色，一有滑动就变回正常颜色，停下来大约一秒后又变暖。

原因在合成路径。drm_hwcomposer 在所有图层都交给 GPU 时（包括静止画面的 flattening），把 CRTC 的 CTM 设成单位矩阵，由 SurfaceFlinger 在 GPU 上乘颜色矩阵（`HwcDisplay.cpp` 里 `client_layer_count == layers_.size()` 那一段）。只要有一个图层上了 plane，它就把夜间模式的矩阵写进 CRTC 的 `CTM`，SurfaceFlinger 这时认为设备处理了颜色变换（`deviceHandlesColorTransform = usesDeviceComposition`），自己不再乘。

硬件这一侧没有效果。`modetest -p` 看到滑动时 CRTC 的 `CTM` blob 是夜间矩阵，静止时是单位矩阵。CCORR（`ccorr@1400f000`，`mediatek,mt8183-disp-ccorr`）的寄存器也跟着变：`DISP_CCORR_EN`=1，`DISP_CCORR_CFG`=0x0a（engine 打开，不是 relay），滑动时系数 R/G/B 为 0x400/0x2fe/0x209（1.0/0.748/0.509），静止时三项都是 0x400。MMSYS 的走线是对的：`RDMA0_SOUT_SEL_IN`=1（到 COLOR0），`DITHER0_MOUT_EN`=1，`DSI0_SEL_IN`=0（从 DITHER0），CCORR 在 COLOR0 和 AAL 之间。静止画面上用 `devmem` 把绿和蓝的系数直接写成 0，保持 10 秒，屏幕颜色没有变化，之后写回 0x400。也就是 CCORR 的矩阵根本没作用到输出上，原因还不知道。

可以走的两条路：

1. 先绕开：给 drm_hwcomposer 加一个属性（例如 `vendor.hwc.drm.use_crtc_ctm=false`），让它把 CRTC 的 CTM 当作不存在，`CtmByGpu()` 返回真，夜间模式打开时所有图层交给 GPU，由 SurfaceFlinger 乘矩阵。代价是夜间模式开着时 GPU 负载更高，平时不受影响。
2. 查清 CCORR 为什么不起作用：对照 ChromeOS 内核（Kukui 上夜间模式走的就是 CCORR）的 `mtk_disp_ccorr.c` 和 `mtk_crtc.c`，看 MT8183 是否需要额外的使能位、shadow 寄存器或 AAL/COLOR 的设置。

## Build 1：调试选项、TPM、RTC、Type-C、唤醒原因

2026-11-09 22:55 起 eMMC 上是这一版。内核 `android.kpart` sha256 `37096745a350e3e538f13fb6188333a50171d754f0559be249dbfca8ab313a8f`，super `c7250707e78486d3efcbabee6519d20ce7c08500a1c0fc78bc5230c4751a0e48`，暂存目录 `stick-update-o`。

配置加了 `PM_SLEEP_DEBUG`、PSTORE（固件已经在 DT 里留了 1 MiB 的 ramoops）、2 MiB 内核日志、MGLRU、THP 改成 `madvise`，关掉 `RTC_HCTOSYS`。vendor_dlkm 多了 `rtc-mt6397`、`tpm_tis_core`、`tpm_tis_spi`、`cros-ec-typec`。新补丁三份：sbs-battery 对 `RunTimeToEmpty` 回 `-ENODATA`；最小的 `/sys/kernel/wakeup_reasons`；ov8856/ov02a10 加系统睡眠回调。

实机结果：dmesg 从 0 秒开始；`/sys/fs/pstore/console-ramoops-0` 有上一次启动的日志；电池 `uevent` 完整；`/dev/tpm0` 是 Cr50 的 TPM 2.0，`rng_current` 是 `tpm-rng-0`；`/sys/class/typec/port0` 出现；`rtc0` 时间正确；一次 RTC 唤醒后 `last_resume_reason` 是 `209 mt6358-irq`，`last_suspend_time` 是 `0.197781462 12.168988231`，suspend-service 不再报读不到唤醒原因；唤醒后相机传感器不再报时钟和稳压器的警告。

相机警告的原因是 6.18 的 PM 核心：没有系统睡眠回调的设备会被当成「没有 PM 回调」，打开 smart suspend，`device_resume_noirq()` 把它直接设成 `RPM_ACTIVE`，随后的 runtime suspend 再关一次从没打开的时钟和稳压器。`pm_ops_is_empty()` 不看 runtime 回调。dw9768 本来就有 `pm_runtime_force_suspend/resume`，所以不受影响。

prng_seeder 在 `early-init` 启动，那时 TPM 模块还没从 vendor_dlkm 加载，它打出 `Hanging forever` 后不退出，init 也不会重启它。`init.kukui.rc` 改成在 `vendor.dlkm.modules.ready=true` 之后 `restart prng_seeder`。在正在跑的系统上手动重启过一次，不再报错。

RTC 的 60 年偏差：之前 PMIC RTC 读出来是 2086-11-08，装上这版之后是正确的时间。原因是 Android 每次设系统时间都会写 `/dev/rtc0`（`com_android_server_SystemClockTime.cpp`，`settimeofday` 之后 `RTC_SET_TIME`）。这次启动日志里先有 `Current time only 20321, advancing to build time`，再有网络时间 `Setting time of day to sec=1794261480`，两次都写了 RTC，现在 RTC 和 UTC 到秒一致。2086 是谁写的还不知道，可能是用别的年份基准的系统或固件。`RTC_HCTOSYS` 先保持关闭：启动 pmOS 一次，再回到 Android、在网络对时之前看 `/sys/class/rtc/rtc0/date`，仍然正确才打开。

## Build 2：开机日志、合盖、深度睡眠、镜头供电

2026-11-10 01:20 起 eMMC 上是这一版。`android.kpart` sha256 `74b1067074f9eecfc383bff569bce1c4fc1de5b5b43db87ecca0b019aab6b289`，super `6ad96f122162abf403d681b7f76380ee2e6aa48ca641bf68c1556afb2f3c2db6`，暂存目录 `stick-update-r`。

- 开机日志：命令行去掉 `drm_client_lib.active=none`，`loglevel=7`，`fbcon=font:TER16x32`，配置加 `CONFIG_FONT_TER16x32`。按 Ctrl+U 之后就是横屏、能读的内核日志。开机动画一起来，`init.kukui.rc` 把 `vtcon1/bind` 写成 0。阶段 3 关掉 fbdev 是和 SET_MASTER 补丁同一步做的；有了那份补丁，drm_hwcomposer 照样拿到 master。
- 合盖：键盘盖的触控板算外接设备，Android 对它的任何移动都会唤醒，而且触控板手势路径固定带 `POLICY_FLAG_WAKE`，`touch.wake` 管不到。合盖时手还在触控板上，屏幕在 lid_switch 睡下去之后 26–124 ms 又被 `WAKE_REASON_WAKE_MOTION` 点亮。`patches/frameworks_base_lid_wake.patch`：盖子合上并且 `lid_behavior` 是睡眠时，移动事件和除电源、WAKEUP 以外的按键都不唤醒。用户合盖时故意碰触控板，屏幕保持熄灭，打开后 `WAKE_REASON_LID` 点亮。
- 深度睡眠：没有保存过选择时，从 eMMC 启动默认 `suspend_power_off=1`，也就是 `deep`。U 盘启动仍是 0。2026-11-09 测过：s2idle 约 53 mA，deep 约 10 mA；deep 下 30 次唤醒都正常，键盘盖唤醒后照常可用。睡眠中按键盘不会唤醒：deep 时 USB 没电，s2idle 时补丁关掉了 USB 唤醒。
- 镜头：相机服务从开机起一直开着 `/dev/v4l-subdev4`，`dw9768_open()` 拿着 runtime PM，`vcamio` 和 `vcama2` 一直有电。`bringup/kernel/dw9768-power-while-streaming.patch` 去掉 open/close 的供电，只在 mtk-seninf 出流时上电。现在不用相机时五路相机电源都关着；用户拍照对焦正常，用完又关掉。
- prng_seeder 在模块加载完之后重启，不再报 `Hanging forever`；`pm_debug_messages` 开机写 1。

Type-C 的数据角色切换没有做成，也做不成。Type-C 插座接在板上 USB 2.0 hub `05e3:0610` 的下游口（hub 在 `1-1`，键盘盖 `1-1.1`，插座上的 U 盘是 `1-1.2`，见 phase-1.md），hub 的下游口不能当 USB 设备，所以没有经数据线的 adb 或 MTP。试过把 `usb@11201000` 改成 `dr_mode = "otg"` 加 `usb-role-switch`：第一次 mtu3 等不到 USB3 MAC 时钟，整个探测失败；加上 `mediatek,u3p-dis-msk` 之后探测成功，但根口上什么都枚举不出来，U 盘启动停在 `no boot partition`。全部撤回，控制器保持 `host`，`cros-ec-typec` 只用来显示 `/sys/class/typec/port0`。

还没处理：开机时 `dlkm_loader_mainline` 在加载 ath10k 时停了约 34 秒（8.50 s 到 42.84 s）。ath10k 请求可选的 `ath10k/pre-cal-sdio-mmc1:0001:1.bin`，`force_sysfs_fallback=1` 让请求等 ueventd 回答找不到，后面的模块和 `vendor.dlkm.modules.ready` 都跟着晚 34 秒。夜间模式见上面一节，也还没处理。

## Build 3：状态栏上图层、内核版本、SELinux 标签、两路解码

2026-11-10 02:30 起 eMMC 上是这一版。`android.kpart` sha256 `8989e795353a47f43d176106c425630be0ad5fe0847db0d172d504b153a229cc`，super `bd5315fa3195729fe8f3df5529dfc0c4c0e4b661ab0472868dd02366795d7b99`，暂存目录 `stick-update-s`。

- GPU 合成：`mtk_drm_kms_init()` 默认帧缓冲最小 64×64，MT8183 没有覆盖。状态栏在面板方向是 42×1920，AddFB2 返回 `-EINVAL`，drm_hwcomposer 把它交给 GPU；客户端图层必须在 z 序上连续，于是夹在缩放壁纸和状态栏之间的全屏启动器也跟着走 GPU。`bringup/kernel/mtk-drm-mt8183-min-fb-size.patch` 把最小值设成 1×1（MT8188/MT8195 本来就是）。滚动时主屏幕的任务栏、状态栏、启动器都上 OVL 图层，只有壁纸是 CLIENT；设置里五个图层全部上图层。
- 内核版本：设置用 `(#\d+) ...` 解析 `uname -v`，`#1-kukui-phase2` 不匹配，显示「不可用」。现在用 `KBUILD_BUILD_VERSION` 写构建序号。
- 两路 H.264 硬件解码，Firefox 同时放两个视频正常。

## Build 4：序列号、BTF、套接字销毁、SELinux 第二批

2026-11-10 20:00 起 eMMC 上是这一版。`android.kpart` sha256 `f1bee3a236d1fd6296ee79c7053f282371894251ec3de50dfdc89de50be6f00c`，super `633b82fea79f869bffb5d0b0d7424a8a9a9d6716be0fa3ad622b42285f2204a3`，暂存目录 `stick-update-t`。

- 序列号：设置里一直是 unknown。Chromebook 的序列号在只读 VPD 里，要靠 `coreboot_table` 和 `vpd-sysfs` 读出来，但 `coreboot_table` 探测返回 `-EINVAL`。6.18 的 OF 核心只有在父节点自己有 `#address-cells` 时才匹配默认总线（`of_bus_default_match`），depthcharge 建的 `/firmware` 只有空的 `ranges`，所以 `/firmware/coreboot` 拿不到地址。`bringup/kernel/mt8183-kukui-firmware-cells.patch` 在 `mt8183-kukui.dtsi` 里先放一个带 2/2 的 `firmware` 节点，depthcharge 往里面填。`kukui-ids.sh` 在模块加载完之后设置 `ro.serialno` 和 `ro.boot.hardware.revision`（`rev6 sku0`）。
- 按应用统计 CPU 时间：`timeInState.bpf` 的 `raw_tp/sched_process_free` 用 CO-RE 读 `task_struct->pid`，内核没有 BTF，libbpf 整个对象都不加载。打开 `DEBUG_INFO_BTF`（构建机要装 `dwarves`），`/sys/fs/bpf/cputimeinstate/` 出现。
- `INET_DIAG_DESTROY`：网络切换时 system_server 不再报 `Failed to destroy socket ... ENOTSUP`。`FS_VERITY` 也打开了，userdata 要重新格式化才会用上。
- 内存盘加了 `iptable_nat`、`ip6table_nat`、`xt_MASQUERADE`、`udp_diag`，`nat` 表有了。共享统计还是报错：netd 的同一批规则里还要 `TCPMSS`，见 Build 5。
- SELinux：触控笔电池单独一个类型（平台域不能读 `sysfs_batteryinfo`），唤醒源 `sysfs_wakeup`，EC 的 extcon `sysfs_extcon`，所有 IIO 设备 `vendor_sysfs_iio`，`/dev/media*` 和 `/dev/v4l-subdev*` 是 `video_device`。first-stage init 冷启动时读过的 `uevent` 文件在策略加载前就有了标签，genfscon 管不到，留到 enforcing 再处理。

## Build 5：Linux 6.18.63、netd 的内核模块

2026-11-10 21:00 起 eMMC 上是这一版。`android.kpart` sha256 `00d5bb5230faed784985d3d69e3c7719edb36cfa9e4f1ba06436d0ff71ea24ae`，super `29ba666d43509917163011949c47bb50e941cc437949156372a5d6bf3710335a`，暂存目录 `stick-update-u`。

- 内核换成 kernel.org 的 6.18.63（校验和与 autosigner 签名都核对过），发布串 `6.18.63-mt81-kukui2`，`#5`。所有补丁只有偏移和 fuzz，配置和 6.18.62 相比只多了下面三项。
- 共享流量统计：netd 建 `tetherctrl_counters` 的那一批规则里有 `-j TCPMSS`，`xt_TCPMSS.ko` 不在内存盘里，整批失败，链从没建出来，NetworkStats 一直报 `failed to fetch tether stats`。内存盘加了 `xt_TCPMSS`，另外打开 `NETFILTER_XT_TARGET_NFLOG`（唤醒包日志）、`NET_CLS_BPF`、`NET_ACT_BPF`，加 `xt_NFLOG`、`sch_ingress`（clsact）、`cls_bpf`、`act_bpf`。现在链存在，不再报错。剩下 `quota2`：那是 Android 内核自己的模块，主线没有，只影响流量上限提醒。
- health HAL 可以读触控笔电池（Build 4 改了类型之后有 146 条拒绝）。

## Build 6：安装器只复制和校验用到的部分

2026-11-10 21:30 起 eMMC 上是这一版。`android.kpart` sha256 `a07b8c323d6b5ad27f0d501829ef949ea652a1cb2f1e6e42bb57498ff88ccc52`，super（稀疏镜像）`ecfde683b3d5748404f7a3f8bc0f9ce38685e60b3cca41ac4d988875a38224c5`，暂存目录 `stick-update-v`。内核和 Build 5 相同。

- 以前「更新系统」把 8 GiB 的 super 整个复制一遍，再把 U 盘和 eMMC 各读一遍 8 GiB 算校验，主要时间花在 U 盘（经板上 USB 2.0 hub，约 35–40 MB/s）读零上。实际内容只有 LP 元数据区和六个逻辑分区，约 1.3 GiB。
- 现在安装器用 `lpdump` 读出分区范围，先对 eMMC 的 super `blkdiscard`，再只复制这些范围（元数据区最后写，中断时不会留下指向半份数据的分区表）。复制时 `tee` 同时算 U 盘那份的校验，U 盘只读一次。之后丢掉页缓存，逐段从 eMMC 读回比对。
- 应用里显示步骤清单（✓ 完成、▶ 进行中、○ 等待、✗ 失败）、进度条和当前在复制或校验哪个分区。
- 写 U 盘也一样：super 用构建出来的稀疏镜像，只写 RAW 和 FILL 块（1295 MiB），跳过 DONT_CARE，按写入的区域读回校验。
