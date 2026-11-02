# 前后摄像头

2026-11-01。路线图在 [roadmap.md](roadmap.md)。不改内核版本字符串，不写 eMMC，不把 Gru 的 `rkisp1` 补丁搬过来。驱动和设备树已经编好，这次 Ctrl+U 上两颗传感器都出了图。方向已确认。软件颜色已确认，两路饱和度是 1.8。Android 相机 HAL 已经放进 `super.camera-hal.raw` 并写入了 U 盘。那张镜像上相机应用一打开就退出。正在跑的系统里换上了修好的 HAL，应用能停住，后摄已经在出帧。录像颜色后来已经确认，带上这些修改的 super 记在文末。

Gru 的笔记在 [docs_from_googlegru/camera.md](docs_from_googlegru/camera.md)。那台是 RK3399 的 `rkisp1`，后摄 `ov5695`、前摄 `ov2685`，色彩靠 ISP 里的黑电平、色彩矩阵和伽马。这台 Krane 没有这条管线。能留的是后半段的接法：相机服务、权限、gralloc，以及录像要等第一帧音频。芯片、调校文件和 `rkisp1` 补丁都不能拿来用。

## 这台机器上的两颗传感器

ChromeOS 内核给 `mt8183-kukui-krane.dtsi` 加过传感器节点（2021-05，`CHROMIUM: dts: arm64: mt8183: Add sensor nodes`）。主线 6.18 的同名文件里没有这些节点，但供电和 EEPROM 还在。

| 角色 | 型号 | 总线 | 分辨率和接口 | 供电和复位 |
| --- | --- | --- | --- | --- |
| 后摄 | OmniVision `ov8856`，对焦马达 `dongwoon,dw9768`（`0x0c`） | `i2c2` 的 `0x10`。旁边的 EEPROM `24c32` 在 `0x58` | 4-lane MIPI CSI-2，链路 360 MHz 或 180 MHz，时钟非连续 | `vcama2` 2.8 V、`vcamd` 1.2 V、`vcamio` 1.8 V。复位 GPIO 111，低有效 |
| 前摄 | OmniVision `ov02a10` | `i2c4` 的 `0x3d` | 1-lane MIPI CSI-2，链路 390 MHz。设备树里写了 `rotation = <180>` | `vcama1` 2.8 V、`vcn18`、`vcamio` 1.8 V。掉电 GPIO 107 高有效，复位 GPIO 109 低有效 |

两路都接到 `seninf`，后摄是 port 0，前摄是 port 1。引脚名里还有 `CLK_5M_WCAM`、`CLK_2M_UCAM` 和 `FCAM_PWDN_L`。

正在跑的系统上，PMIC 里这四路都在，而且都是关的：`vcamio` 1.8 V、`vcamd` 1.2 V、`vcama1` 2.8 V、`vcama2` 2.8 V。I2C 上已经探到的是 `2-0058` 和 `4-0050` 两颗 EEPROM，没有 `0x10`、`0x0c`、`0x3d`。传感器没写进设备树，驱动也不会去开电，所以这次没有直接读到传感器的芯片 ID。ChromeOS 这份板级节点和后来在同一块 `google,krane-sku176` 上跑通的主线移植，型号是一致的。

主线 `i2c4` 的 EEPROM 地址是 `0x50`，ChromeOS 补丁上下文里写的是 `0x54`。正在跑的机器是 `4-0050`。传感器地址以 `0x3d` 为准，不要把 EEPROM 地址当成前摄。

## 这次开机实际有什么

2026-11-01，无线 adb `10.0.0.104:5555`，内核仍是 `6.18.28-mt81-kukui2`，super 是 `super.poll.raw`。

- `/dev/video0` 是 `mtk-vcodec-dec`，`/dev/video1` 是 `mtk-vcodec-enc`，`/dev/media0` 是它们的。没有 `/dev/v4l-subdev*`。
- `dumpsys media.camera` 报 0 个相机。`ro.hardware.camera` 是空的，`/vendor` 里没有相机 HAL，也没有相机相关的 `.ko`。
- 6.18 的 `mt8183.dtsi` 和 `mt8183-kukui-krane.dtsi` 都没有 `seninf`、CAMSV 或传感器节点。`CONFIG_OF_OVERLAY` 没打开，运行中加不了节点。
- 源码里有 `ov8856.c`、`ov02a10.c`、`dw9768.c` 和 `phy-mtk-mipi-csi-0-5.c`，配置都没打开。这颗 CSI PHY 只认 `mediatek,mt8365-csi-rx`，没有 MT8183。`seninf` 和 CAMSV 的驱动不在这棵树里。

ChromeOS 自己的相机栈走完整 ISP，还要配套的下游内核。那条不进 6.18，也不借用 SCP 固件。SCP 已经留给视频解码。

同一块 sku176 上有一条已经跑通的路：传感器经 CSI-2 D-PHY 进 `seninf`，再由 CAMSV 把原始 Bayer 直接 DMA 出来，用户态用 libcamera 的 simple 管线和软件 ISP 做去马赛克。不经过 ChromeOS 的 ISP，也不用 SCP。Debian 13、Linux 6.12.50 上，后摄 8 MP 和前摄 2 MP 都能出图。6.18.28 里还没有 `seninf` 和 CAMSV，CSI PHY 也还没有 MT8183 的兼容串，所以不能只打开现成模块。

## 建议的做法

先拿到一帧，再接 Android。不要一上来编相机 HAL，也不要套 Gru 的 `ov5695.yaml`。

1. 内核仍是 `6.18.28-mt81-kukui2`，版本字符串不动。把 `seninf` 和 CAMSV 作为模块补进这棵树，CSI PHY 加上 MT8183 能用的兼容串。同时把已经在树里的 `ov8856`、`ov02a10`、`dw9768` 编成模块。不引入 ChromeOS 的完整 ISP。
2. 设备树要加传感器、PHY、`seninf` 和 CAMSV。现在的 FIT 里没有这些节点，overlay 也没打开，所以这一步会改内核分区里的 DTB，和写 super 不是同一件事。模块和 DTB 对上之后再写内核槽。写之前仍只动 SanDisk，不写 eMMC。
3. 节点按 ChromeOS 的 Krane 连接来：后摄 `i2c2` 的 `0x10` 加 `0x0c` 对焦，前摄 `i2c4` 的 `0x3d`。EEPROM 保持现在的 `2-0058` 和 `4-0050`。先确认两颗传感器都出现在 media graph 里，再抓几帧原始数据。这一步还不谈颜色。
4. 用户态用 libcamera 的 simple 管线加软件 ISP，用 `cam` 列出两颗摄像头并各抓一张。颜色在软件里完成。Gru 那套黑电平和色彩矩阵是 `rkisp1` 的，这里用不上。前摄设备树写了 180 度，等看到画面再定 Android 里的旋转，不照抄 Gru 的 `rotation: 90`。
5. 画面确认之后再接 Android。`camera.libcamera`、`android.hardware.camera.provider-service.lineage`、`camera_hal.yaml` 里的前后位置，以及 `android.hardware.camera` 和 `android.hardware.camera.front` 的特性声明，接法可以参考 Gru。权限上 Gru 后来补过的、和芯片无关的部分也要留：相机 HAL 读传感器 sysfs、memfd 队列、gralloc mapper 和 `vendor.minigbm.device`。预览和 JPEG 拍照先做。录像排在拍照之后。Gru 上计时停在 `00:00` 是因为录像在等第一帧麦克风数据；这台的内置麦要单独再听一次，不和出图绑在一起。

## 做到出图之前

2026-11-01。内核映像没有重链，版本字符串仍是 `6.18.28-mt81-kukui2`，`#1-kukui-phase2 SMP PREEMPT Sat Oct 31 19:57:12 EDT 2026`。`Image.gz` 的 sha256 仍是 `5e35983d0174a99a924a4152cc23f4a2074587de0503b7ba335d2e3d09195c72`。

`seninf` 和 CAMSV 放进 `drivers/media/platform/mediatek/isp/`，按模块编。源在 [bringup/camera/isp](../bringup/camera/isp)，对 6.18 的改动是 `v4l2_get_link_freq()` 改成传入传感器的 media pad。CSI PHY 加上 `mediatek,mt8183-csi-rx`。`ov8856`、`ov02a10`、`dw9768` 编成模块。`ov8856` 打开子设备或读格式时不再把 Bayer 顺序打回默认。`videodev` 打开了 subdev streams 接口，否则两颗传感器会落到同一个 CAMSV 节点。这些对现有文件的改动在 [bringup/camera/kernel-camera.patch](../bringup/camera/kernel-camera.patch)。配置片段在 [bringup/camera/config.fragment](../bringup/camera/config.fragment)。

设备树没有整份重编。正在用的 FIT 里那块 `mt8183-kukui-krane-sku176.dtb` 接上摄像头节点：后摄 `i2c@11009000` 的 `0x10` 和 `0x0c`，前摄 `i2c@11008000` 的 `0x3d`，两路 CSI PHY、`seninf`、两路 CAMSV。EEPROM 仍是 `0x58` 和 `0x50`。新的内核分区是 `work/phase4/kernel.kpart.camera`，12517376 字节，sha256 `c2aceff91dddd39b1bdefc79f0f4ff84bc164e20615dbb805d1bfc30d3bf5f54`。里面的内核 lzma 校验和仍是 `f3ea1c10`，ramdisk 仍是 `e429f3ea`，命令行没变。

模块放进 vendor_dlkm，排在 `videobuf2-v4l2.ko` 后面：`v4l2-async`、`v4l2-fwnode`、CSI PHY、`mtk-seninf`、`mtk-camsv`、`dw9768`、`ov8856`、`ov02a10`。`videodev.ko` 换成打开了 streams 接口的那份，vermagic 仍是 `6.18.28-mt81-kukui2 SMP preempt mod_unload aarch64`。super 是 `work/phase4/super.camera.raw`，8589934592 字节，sha256 `9e44d7e1dbf9fb901c863a275d419bb79818f04fe99f4b419677f2fc3a07992b`。

2026-11-01 只写了 SanDisk（序列号 `000000002959`）的内核槽和 super。内核槽读回 sha256 `c2aceff91dddd39b1bdefc79f0f4ff84bc164e20615dbb805d1bfc30d3bf5f54`。super 读回 sha256 `9e44d7e1dbf9fb901c863a275d419bb79818f04fe99f4b419677f2fc3a07992b`。pmOS_boot、metadata、misc、userdata 的开头 1 MiB 没有变。卡已卸载。eMMC 没写。

同日 Ctrl+U 之后，两颗传感器都绑上了：后摄 `ov8856 2-0010`、对焦 `dw9768 2-000c`、前摄 `ov02a10 4-003d`。EEPROM 仍是 `2-0058` 和 `4-0050`。media graph 上的链路是通的：后摄进 `seninf` pad 0，再进 `1a050510.camsv`；前摄进 pad 1，再进 `1a051510.camsv`。

把视频节点设成和传感器一样的尺寸之后，各抓到一帧，没有 `IMGO` 错误。后摄 1632×1224 `GRBG`，1997568 字节；前摄 1600×1200 `RGGB`，1920000 字节。没设尺寸时 CAMSV 停在默认的最大分辨率，后摄会连续报 `IMGO` 错误 `0x10000`。方向已确认：ov8856 是后摄，ov02a10 是前摄，设备树里的 180 度不用改。

接着在这台上跑了 libcamera 0.7.1 的 simple 管线加软件 ISP（CPU 去马赛克）。`/dev/dma_heap/reserved` 太小，分配会失败，改用 `system` 堆之后两路都能出图。前摄 1596×1200，天花板和墙接近实景。后摄 1628×1220，来自 1632×1224 `GRBG`。原始数据按 GRBG 解出来床单是绿的，软件 ISP 却偏紫：白平衡按减过黑电平的统计给红通道大约 1.76 倍增益，伽马表却把黑电平留在增益之后，红通道的底被一起放大。查找表改成先减黑电平再乘增益之后，同一张床单的采样均值从大约 R 54、G 15、B 37 变成 R 38、G 41、B 41，画面呈淡薄荷绿，花是浅粉。两路的饱和度都停在 1.0，灰世界白平衡把颜色往灰里拉，看起来发灰。调校文件里 `Adjust.saturation` 设成 1.8 之后，后摄色度从大约 7.5 升到 12，床单仍是薄荷绿，花更粉，旁边的毯子呈深蓝；前摄色度从大约 9.6 升到 18.5，墙是米色，天花灯仍略偏粉。颜色已确认。当时那份 `libcamera.so` 只推到正在跑的系统。两颗都没有 libcamera 的传感器参数，曝光和增益是猜的。软件去马赛克跟不上传感器，抓到的大约是 7.5 帧每秒。

同一套 libcamera 0.7.1 编成了 Android 相机 HAL，放进 `work/phase4/super.camera-hal.raw`，8589934592 字节，sha256 `6ee9cc4b1d3661144aa75bc829ddc3f8d0c49bc1cd1c620735cea0e360c067f3`。内核槽不用换，仍是已经在 U 盘上的 `kernel.kpart.camera`。`vendor/lib64/hw/camera.libcamera.so` 是这份 HAL，`ro.hardware.camera=libcamera`，provider 是 `android.hardware.camera.provider-service.lineage`。软件 ISP 仍输出 RGB888，HAL 里转成预览用的 NV12，JPEG 直接吃这份 RGB。后摄 ov8856 注册成相机 0。`camera_hal.yaml` 里后摄是 back、前摄是 front，旋转都是 0，不再加一层。设备树里前摄的 180 度保持不动。调校文件在 `/vendor/share/libcamera/ipa/simple/`，饱和度仍是 1.8。`/dev/dma_heap/system` 交给 `camera` 组。IPA 代理在 `/vendor/bin/libcamera/soft_ipa_proxy`。2026-11-01 只把这张 super 写入 SanDisk（序列号 `000000002959`）。读回 sha256 `6ee9cc4b1d3661144aa75bc829ddc3f8d0c49bc1cd1c620735cea0e360c067f3`。内核槽、pmOS_boot、metadata、misc、userdata 的开头 1 MiB 没有变。卡已卸载。eMMC 没写。预览和 JPEG 当时都还没在相机应用里看过。

这张 `super.camera-hal.raw` 上相机应用一打开就退出。provider 在跑，但是两颗相机都没完成初始化：simple IPA 没有公布 `FrameDurationLimits`，HAL 因此拒绝注册，`dumpsys` 里是 0 个相机。Aperture 抛出没有可用相机。再点一次模式时配置是空的，那是同一次失败的后续。把帧间隔补上之后，HAL 还会丢掉所有低于 30 fps 的预览尺寸，只剩 JPEG。CPU 去马赛克实际大约 7 到 8 帧每秒，对外仍报 30 fps，否则预览尺寸会被全部丢掉。宽度不是 64 的倍数的分辨率也去掉了，minigbm 会把 NV12 的行补到 64 字节。

会话接着被拒绝。预览和 JPEG 都是 1600×1200，合成一路 RGB888。管线只是补上了缓冲区数量和色彩空间，却报成 Adjusted，HAL 把这当成失败。改成只拒绝尺寸或格式被改掉的情况之后，会话能配上。接下来 provider 在克隆请求元数据时断言失败：HAL 自己带的 `camera_metadata` 和框架发下来的结构不一致，改成链接系统里的 `libcamera_metadata.so`。内部的 RGB 缓冲不能向 minigbm 要 `YCbCr_420_888`，它直接返回 EINVAL，改从 `/dev/dma_heap/system` 分配。预览缓冲是 minigbm 的两路 fd，HAL 原先只接受单个连续 fd，按 `cros_gralloc_handle`（magic `0xABCDDCBA`）读每路的 fd、偏移和 stride。

2026-11-01 晚上，这些改动先从 userdata 挂到正在跑的系统上验证。Aperture 保持打开，相机 0 是后摄 1600×1200，软件 ISP 输入 1632×1224 GRBG。30 帧花了大约 3.9 秒，还是 7 到 8 帧每秒。没有开始录像。同一天把修好的 HAL、IPA 和 Vulkan 写进 `work/phase4/super.vk.raw`，8589934592 字节，sha256 `a4ab55590721edc89fc5440d7ec328047e47d027b71315e49791d6219eb75ed7`。只写入 SanDisk（序列号 `000000002959`）的 super。读回一致。内核槽开头 1 MiB 没变。卡已卸载。eMMC 没写。还没有这次 Ctrl+U。

预览跑了大约 16 秒之后 provider 收到 SIGPIPE，init 把整个进程杀掉，下一次打开就是 0 个相机。libcamera 往已关闭的套接字或 init 的日志管道写数据时，默认会用 SIGPIPE 结束进程。`libcamera-base` 现在忽略 SIGPIPE，套接字发送带 `MSG_NOSIGNAL`，改成返回 EPIPE。

预览能保持打开之后，前后摄都是一片纯绿，上半截没有细节，下半截只有绿色的明暗。`HW_CAMERA_WRITE` 让 minigbm 把预览缓冲分配成 NV12，这块 dumb 显示把色度面读成 0，亮的地方就饱和成纯绿。去掉这个 usage 之后，同一块缓冲变成 XBGR8888，HAL 把软件 ISP 的 BGR 写进去。截图里后摄能看到深蓝毯子和床单，前摄能看到人和窗帘，红绿蓝都有数值，不再是纯绿。颜色已确认正常。这些改动已经在 `super.vk.raw` 里。

取景框慢不是整机没算力。后摄 CAMSV 中断大约每秒 31 次，传感器在出 30 帧。SurfaceFlinger 上预览实际是 7.6 帧每秒，间隔平均 132 毫秒。两根 `DebayerCpu` 线程各占满一个大核（cpu4–7，2.0 GHz），另外两个大核和四个小核空着，所以功耗停在 5 W 出头。软件 ISP 默认只开 2 个线程，而且每帧都要把 1632×1224 的整幅 Bayer 做完才送给预览。预览在等这一帧算完，不是在等传感器。

同一份 libcamera 0.7.1 里本来就有 GLES 2 去马赛克（`DebayerEGL`，McGuire 的 Bayer 片元着色器）。Android 这次编译把它打开了，没有另写一套 Vulkan 计算着色器。片元通道不占用那条 500 毫秒就会复位整颗 GPU 的计算作业槽。着色器仍然是先减黑电平，再乘色彩矩阵、对比度，然后做伽马，和已经确认过的 CPU 查找表不是同一条顺序，所以颜色可能和现在不一样，这次没有提前重调。GPU 路径只输出 32 位 `XRGB8888`（内存里是 B、G、R、X），HAL 在映射预览格式时优先选它，CPU 退路也能出同一种格式。预览仍写进已经确认过的 XBGR8888 gralloc 缓冲，JPEG 和缩略图按 4 字节一行来读。无窗口 EGL 上下文建不起来时，构造函数退回 CPU，预览格式仍是这一种。

第一次挂上去的时候取景仍是两根 `DebayerCpu`。`/vendor/etc/libcamera/configuration.yaml` 里写着 `software_isp.mode: cpu`，GPU 路径根本没被构造。改成 `gpu` 之后，Android 的 `libEGL` 拒绝 `EGL_PLATFORM_SURFACELESS_MESA`，`eglGetDisplay(EGL_DEFAULT_DISPLAY)` 才能拿到 Mesa 25.3.3 的 OpenGL ES 3.1。上下文起来之后，预览拷贝还是逐像素交换 R 和 B，单线程把出帧压在大约 20 帧每秒。改成 libyuv 的 `ARGBToABGR`，输出 dma-buf 按 fd 缓存，Bayer 纹理用 `glTexSubImage2D`，整库用 `-O2` 重编。

2026-11-01 晚上这版从 userdata 挂上：`libcamera.so` sha256 `ea117bfd37849064d2435e6834d9909df0a37b2d4ab6d9444015d604ef188af7`，`camera.libcamera.so` sha256 `c0e1aeb9fc51bca246c778ad269fe7bf3ad39e874b7b52ae9d5c0c24ff3c416e`，`libcamera-base.so` sha256 `b06235c9233ceeceee75bb1d80a56332da7e94c162012e47ce09187254224fa8`。进程里没有 `DebayerCpu`，只有 `SWIspWorker`。日志是 `GL_VERSION: OpenGL ES 3.1 Mesa 25.3.3`。去马赛克本身大约 25 毫秒一帧。HAL 的 `Frames produced` 在 2 秒里从 294 增到 356，大约 31 帧每秒，和传感器中断一致。颜色有没有偏还要看画面。没有写 U 盘，没有重启平板。

取景比传感器小一圈时，片元着色器用一个插值判断 Bayer 相位，用另一个插值决定取样落在哪个像素。缩放后有些行和列正好落在像素边上，两边各进一位，这一行或这一列的红蓝高于绿，就是洋红色细线。后摄 1632×1224 收到 1600×1200，横竖都会碰到；前摄如果高度没缩，就只剩竖线。改成先把源像素坐标做一次 `floor()`，相位和相邻取样都从这一个整数来。截图里后摄和前摄（1280×960）都不再有贯穿画面的洋红色线。正在跑的 `libcamera.so` sha256 是 `b119f2c6085ce21b1326ff5c4121562b437f3e61442f4473295f3e9b9e44f293`。

拍照和录像之前没有别的相机功能还没做。对焦马达没有单独接上，预览和这张照片都还能用。

快门第一次把 provider 打崩了。JPEG 写在 gralloc 缓冲末尾的 `camera3_jpeg_blob` 上，这块缓冲比 1600×1200 的像素面大，原来只映射了像素面，补写位置落到映射外面。现在按 gralloc 的宽度（BLOB 是一行，高度为 1）映射，页脚先清零再写，16 位和 32 位的读取都能对上 `0xff`。2026-11-01 23:30 后摄拍下 `DCIM/Camera/2026-11-01-23-30-53-253.jpg`，715353 字节，Exif 1600×1200，能解码，画面是床单、枕头和键盘。拍照已经确认正常。

录像同时要预览和一条更大的视频流时，simple 管线会挑能盖住请求、又不放大的最小传感器模式。1920×1080 盖不住 1632×1224，于是进了 3264×2448，去马赛克和预览一起掉到大约 5 帧每秒。没有 JPEG 的录像会话现在把 libcamera 的输出限制在 1600×1200，留在分箱模式上，再在 HAL 里裁成 16:9 后转 NV12、缩放。2026-11-01 23:39 那条 4.9 帧每秒、没有音轨的 1080p 是改之前的。

编码器节点是 `/dev/video3`（`mtk-vcodec-enc`，采集队列 H.264，输出 NM12）。codec2 进程是 `media`，不在 `camera` 组，打不开 `0660` 的 `/dev/video3`，组件列表里就没有 `c2.v4l2.avc.encoder`。`/dev/dma_heap/system` 同样只给了 `camera` 组，`media.swcodec` 分配线性缓冲被拒绝，AAC 和 Vorbis 都在 `start` 上报 `NO_MEMORY`，文件里没有音轨。这次把这两个节点临时改成了 `0666`。下次镜像里 `ueventd.kukui.rc` 把 system 堆改成 `0666`，codec2 服务加入 `camera` 组。重启会丢掉这次的临时权限。

权限放开之后，录像走 `c2.v4l2.avc.encoder`。正在跑的系统没有 `media_profiles_V1_0.xml`，CameraX 的质量列表里没有 1080p，新开的会话落到 720p。`device/google/kukui/etc/media_profiles_V1_0.xml` 补了 1080p/720p/480p，音频是 48 kHz 立体声，要等下一份镜像。2026-11-02 00:16 的 `DCIM/Camera/2026-11-02-00-16-38-162.mp4` 是 2.46 秒，H.264 Baseline 1280×720，大约 26 帧每秒（48 帧里 40 帧间隔小于 40 毫秒），AAC-LC 44100 Hz 单声道 96 kb/s。没在录像时，视频取景的 `Frames produced` 两秒从 152 增到 214，大约 31 帧每秒。录像进行中的两秒里，预览和视频各增加大约 57 帧。录像帧率已经确认。声音还没有人听过。

绿色和洋红是缓冲格式搞反了。`HW_CAMERA_WRITE` 会让 minigbm 分配 NV12。预览必须去掉它，否则 dumb 显示把色度读成 0，整屏发绿。录像正好相反：编码器把这块缓冲当 NV12 来压。两个标志都清掉时，实现定义格式落到 XBGR8888，编码器把 B、G、R、X 的字节当成亮度和色度，暗的地方发绿，亮的地方发洋红，还会重出一层影子。现在只有已经带了 `GRALLOC_USAGE_HW_VIDEO_ENCODER` 的那条流才加上 `HW_CAMERA_WRITE`。

NV12 配上之后，720p 仍然只有下半幅是画面，上半幅发灰而且有重影，分界正好在高度的一半。480p 走软件编码器时则整幅发绿，上半几乎没有细节。色度面和亮度面在同一个 dmabuf 里，色度从 `stride × height` 开始。HAL 按这个偏移去 `mmap`，dma-buf 却从对象开头映射，色度就写进了亮度的上半幅。硬件编码器也不看 `data_offset`，两路平面的地址都是这块缓冲的开头，于是上半幅亮度变成色度，下半幅才是画面。软件编码器按 gralloc 的偏移去读色度，那里仍是 0，整幅就发绿。

HAL 现在从 dmabuf 开头映射，再自行加上平面偏移。编码器模块 `mtk_vcodec_enc` 把 `data_offset` 加进平面的 DMA 地址。2026-11-02 01:26 的 `DCIM/Camera/2026-11-02-01-26-12-842.mp4` 是 1280×720，整幅都有画面，第 359 行和第 360 行的亮度不再断开，色度在 128 附近而不是 0。01:25 的 640×480 同样是整幅，不再上绿下绿。录像颜色已经确认正常。

拍照切到录像时应用报 “Error while setting up the session” 然后退出，是因为有一帧的传感器时间戳是 0。框架把快门时间 0 当成“还没到”，这帧元数据和缓冲都回来了也永远留在在途队列里。下一次建会话要等这帧排空，大约 5 秒后超时，错误码 3 接着 4，活动被关掉。HAL 现在把非递增的时间戳换成单调时钟，并写回同一份结果元数据。2026-11-02 00:57 连续做了拍照→录像→拍照→录像→拍照→录像，每次都重新配上了对应的流（录像是 1600×1200 加 1280×720，usage `0x30030`；拍照是 1600×1200 加 MJPEG），应用一直停在 Aperture，没有错误码。切换已经确认。

确认颜色时，正在跑的 HAL 还是 userdata 上的绑定：`camera.libcamera.rec9.so`，sha256 `9e0ab77c6eaab2e021d96df9b2398bdb294c84c37c5491acb6f72b7c53f410cc`。`libcamera.so` 是 `libcamera.rec3.so`，sha256 `11def3e08e458c8f2493ef0c3f8dabd0e4b6c15d5b1695fb9e423925f1ca825b`。2026-11-02 把同一份源码重新编进了镜像。HAL sha256 `90952c517b06e12979b4efd2838e7daca6395a22b1ade37baecfea67a3d55e1d`，`libcamera.so` sha256 `a93c177cb5cbc402f78e43ae60e247db5514bd23ab2b351b5dd8dfc9955659fd`，`libcamera-base.so` 仍是 `b06235c9233ceeceee75bb1d80a56332da7e94c162012e47ce09187254224fa8`。编码器模块 sha256 `ece7fd4de41d7a6e3537c8c373486315270edc4282fa45aef802ecf1ea398da4`，放在 `vendor_dlkm`。`ueventd.kukui.rc` 把 `/dev/dma_heap/system` 交给 `0666`，codec2 服务加入 `camera` 组，所以 `/dev/video*` 保持 `0660`。`media_profiles_V1_0.xml` 也放进了 vendor。super 是 `work/phase4/super.cam.raw`，8589934592 字节，sha256 `e58df4603da72075515bc54f004afd8c7e8a57ce6da53cbfb3ca1ba2f41665cf`。只写入 SanDisk（序列号 `000000002959`）的 super。读回一致。内核槽开头 1 MiB 仍是 `1ebedee8e582b76f78dd6f3b7468ca3d4a1c5164c222ce11aacf66d7df9ed545`。pmOS_boot、metadata、misc、userdata 的开头 1 MiB 没有变。卡已卸载。eMMC 没写。还没有这次 Ctrl+U。
