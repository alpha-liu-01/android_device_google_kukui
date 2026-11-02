# 音视频硬件编解码

2026-11-01。路线图在 [roadmap.md](roadmap.md)。这一篇只调查，不改内核版本字符串，不写 eMMC，不把 Gru 的 rkvdec 补丁搬过来。阶段 4 的日常功能已经收口，编解码从这里单独做。

Gru 的笔记在 [docs_from_googlegru/video-decode.md](docs_from_googlegru/video-decode.md)。能用的是接法，不是那颗 RK3399 的驱动和补丁。下面先写这台机器上看到的东西，再写哪些笔记能留。

## 这次开机实际有什么

2026-11-01 无线 adb `10.0.0.104:5555`，内核仍是 `6.18.28-mt81-kukui2`。`/dev/video*` 和 `/dev/media*` 都不存在，`/sys/class/video4linux` 是空的。平台设备在，驱动没有绑上：

| 设备 | 兼容串 | 驱动 |
| --- | --- | --- |
| `16020000.video-codec` | `mediatek,mt8183-vcodec-dec` | 无 |
| `17020000.vcodec` | `mediatek,mt8183-vcodec-enc` | 无 |
| `17030000.jpeg-encoder` | `mediatek,mt8183-jpgenc` | 无 |
| `14003000.mdp3-rsz0` 等 | `mediatek,mt8183-mdp3-*` | 无 |
| `10500000.scp` | SCP | 无。`/sys/class/remoteproc` 是空的 |

配置都是模块：`CONFIG_VIDEO_MEDIATEK_VCODEC=m`，`CONFIG_MTK_SCP=m`，`CONFIG_V4L2_H264=m`，`CONFIG_V4L2_VP9=m`，`CONFIG_VIDEO_MEDIATEK_JPEG=m`，`CONFIG_VIDEO_MEDIATEK_MDP3=m`。`CONFIG_MTK_IOMMU=y`。镜像的 vendor 里没有这些 `.ko`，也没有 `mediatek/mt8183/scp.img`。所以阶段 0 在 postmarketOS 上看到的 `/dev/video3`，到这份 Android 里还没被装起来。

EC 仍走 SPI `11012000.spi:cros-ec@0`。设备树里 SCP 下面还有一个 `google,cros-ec-rpmsg`，这次开机没有用它。加载 `scp.img` 是为了解码器，不是为了换掉这颗 SPI EC。

## 解码器

`mtk_vdec_8183_pdata` 把接口设成无状态 Request API：`uses_stateless_api = true`，输出队列 `requires_requests`。没有子设备（`is_subdev_supported = false`），所以 `mtk-vcodec-dec-hw.ko` 不是这颗芯片的路径。固件走 `mediatek,scp = <&scp>`，文件名是设备树里的 `mediatek/mt8183/scp.img`。

打开设备时，驱动向 SCP 要能力字。不管能力字写什么，这颗 pdata 都会再或上 H.264 slice 和 `MM21`。VP8、VP9、HEVC、AV1 只有能力字带了对应位才出现。模块依赖里同时写了 `v4l2-h264` 和 `v4l2-vp9`，所以阶段 0 说「拉起了这两个模块」只说明 `.ko` 链在一起，不能当成已经枚举出 VP9。

设备树的寄存器块里有 AVC、VP8 和 VP9。驱动为 VP8 注册 `V4L2_CID_STATELESS_VP8_FRAME`，为 VP9 注册 `V4L2_CID_STATELESS_VP9_FRAME`。没有 rkvdec 那种 `V4L2_CID_STATELESS_VP9_COMPRESSED_HDR`。H.264 等级上限是 4.2，轮廓是 High。VP9 在这颗芯片上的等级默认是 4.0，轮廓到 Profile 1，8 bit、只收 4:2:0。10 bit 的 `MT2110` 要能力字另带一位，8183 的这条路径不该当成可用。

默认编码尺寸是 64×64 到 2048×1088，步进 16。能力字若没有 `VCODEC_CAPABILITY_4K_DISABLED`（`0x10`），H.264 和 VP9 的上限会被改成 4096×2304。VP8 保持 2048×1088。这个字要等 SCP 起来之后读，现在还没有。

输出格式不是 NV12。无状态路径登记的捕获格式是 `MM21`：两平面，16×32 的块。`MT21C` 同样要能力字。合成器和 gralloc 按线性 NV12 读的话，画面会对不上。

`mtk-vcodec-dec.ko` 的依赖是 `mtk-vcodec-common`、`v4l2-mem2mem`、`videodev`、`videobuf2-v4l2`、`videobuf2-common`、`videobuf2-dma-contig`、`v4l2-h264`、`v4l2-vp9`、`mc`、`mtk-vcodec-dbgfs`。SCP 模块要先于解码器。

## 编码器、JPEG、MDP

编码器 `mediatek,mt8183-vcodec-enc` 是有状态的，不是 Request API。这颗 pdata 的压缩格式只有 H.264，码率 64 bit/s 到 40 Mbit/s。原始帧是多平面的 `NV12M`、`NV21M`、`YUV420M`、`YVU420M`，不是单平面 `NV12`。VP8 编码只在 mt8173 那份 pdata 里。`mtk-vcodec-enc.ko` 不依赖 `v4l2-h264`。它同样要 SCP。

JPEG 编码器是另一颗设备，不走 SCP。MDP3 是缩放和颜色转换，不是编解码器。这两样这次不接进播放路径。内置屏播放先靠解码器。

## 音频

没有单独的 AAC、MP3 或 Opus 硬件解码器。`MT6358` 是模拟声卡，阶段 4 已经接到播放和录音。压缩音频继续走 `c2.android.*`。这一篇不重做声卡。

## Gru 的笔记能用多少

能沿用的是用户空间接法，而且这棵 Lineage 23.2 树里已经有：

- `external/v4l2_codec2` 的 `StatelessV4L2Decoder` 通过 `libcros_codecs_ffi` 调用 `system/cros-codecs`。有状态的 `V4L2Decoder` 不会分配 media request，解不了这颗芯片。
- `cros-codecs` 找 `/dev/media*` 时写了：`mtk-vcodec` 不填 `bus_info`，要退回按驱动名匹配。这是对这颗驱动的，不是对 rkvdec 的。
- `device/mainline/common/optional/v4l2_codec2/product.mk`。`TARGET_MEDIA_C2_HAL=v4l2_codec2` 会装 `android.hardware.media.c2-service-v4l2` 和 seccomp 策略。Kukui 的 `device.mk` 还没有设这个变量。
- 先用 `ccdec` 对节点试解，再接到 `MediaCodec`。Gru 就是这个顺序。
- 阶段 4 已经打过的 v4l2 seccomp（`fcntl`、`uname`）留着。

不要搬的：

- `hantro-vpu.ko`、`rockchip-vdec.ko`，以及 Gru 的 `/dev/video0..2` 编号。
- rkvdec 的 NV12 跨距补丁。那边是单平面 NV12，dumb pitch 按 64 对齐，硬件按 16 对齐写。这边捕获格式是两平面 `MM21`。
- rkvdec 的 VP9「上一帧运动矢量」补丁，以及「用户空间必须下发压缩头」那一条。这颗驱动要的是 `V4L2_CID_STATELESS_VP9_FRAME`，压缩头在 SCP 里。VP9 如果花屏，按这颗驱动查，不把那份补丁先打上。
- Gru 的 `debug.stagefright.c2-poolmask=0x70000`。那是那边 ByteBuffer 退回基本池之后改的。这边先用 mainline 那份示例值，复现了再改。
- 示例 `media_codecs_c2.xml` 里的 VP8/VP9 编码器，和 secure AVC。这颗 pdata 没有这些格式，清单里不要照抄。

## 实现顺序

1. 只加模块和固件，不重编内核、不改版本字符串。按依赖装上 `mtk_scp`、videobuf2、`v4l2-mem2mem`、`v4l2-h264`、`v4l2-vp9`、`mtk-vcodec-common`、`mtk-vcodec-dec`，固件放到 `/vendor/firmware/mediatek/mt8183/scp.img`。固件用这台机器 postmarketOS 已经在用的那份，先核对许可证，不拿别的板的 `scp.img`。加载之后确认 SPI EC、电池和传感器还在。然后读解码器的格式和能力字，确认 H.264、VP8、VP9 哪些真的出现，捕获格式是不是 `MM21`。
2. 节点稳定之后，用 `ccdec` 解一段 H.264 和一段 VP9，对照软解的画面。这一步不过，就不接 `MediaCodec`。
3. `MM21` 不能直接交给 Surface。`cros-codecs` 里有 CPU 反块，也有一份 Vulkan 着色器。这台机器的显示走 GLES，Vulkan 还没开，先用 CPU 反块得到线性 NV12，再交给 gralloc。1080p 若赶不上帧，再看 MDP3 能不能做同样的转换。不先改 minigbm 的 NV12 pitch。
4. `device.mk` 打开 `TARGET_MEDIA_C2_HAL=v4l2_codec2`。媒体清单只写第 1 步枚举到的解码器，外加 H.264 编码器（输入按 `NV12M` 核对，对不上就先不做编码）。属性用 `ro.vendor.v4l2_codec2.decoder.supported.*` 把没枚举到的格式关掉。
5. 实机播放。网页和本地文件走 `c2.v4l2.avc.decoder`，VP9 只有第 1 步出现了才开。HEVC、AV1 和安全解码保持软解或不提供。编码器、JPEG、MDP 不挡播放。

## 2026-11-01 做到第 4 步

第 1 步在当前这次启动上加载，没有重编内核。固件是这台机器 postmarketOS 的 `mediatek/mt8183/scp.img`，解压后 1030776 字节，sha256 `401e9c027b0e105efa9eb9b31683924a8d5f5ab3b1654f0915b174effe2df33d`。内核报的版本是 `kukui_scp_v2.0.13324-280b9fce97`，和 linux-firmware WHENCE 里 mt8183 那条一致。许可证是 `LICENCE.mediatek`：可以随带 MediaTek 芯片的设备再分发，固件本身不能改成 GPL。SPI 电池仍是 100%、Full，加速度计仍有读数。SCP 上的 `cros-ec-rpmsg` 也注册了一个 EC，没有把 SPI EC 换掉。

解码器 `/dev/video0` 只列出 `S264` 和捕获 `MM21`。VP8、VP9 的 TRY_FMT 返回 EINVAL。1920x1088 和 2048x1088 的 `MM21` 能过，4096x2304 被收成 2048x1088。编码器 `/dev/video1` 的原始输入是 `NM12`（NV12M），码流是 H.264。

第 2 步用 `ccdec` 解了 10 帧 640x360 baseline H.264，输出 I420。和 ffmpeg 软解逐字节相同，sha256 `1bb4b34778fa8186d147229da3828257f3e40b057e876cfed23c578d9fa60b96`。VP9 没有枚举到，没有测，也不进清单。

第 3 步不把 gralloc 的一张 fd 直接交给解码器。这颗驱动两个平面各取自己的 dma 地址，不加 `data_offset`，Y 和 UV 会写到同一处。解码进驱动自己的 mmap 缓冲，再用已有的 `mm21_to_nv12` 抄成线性 NV12。补丁在 `patches/system_cros_codecs.patch`。

第 4 步打开了 `v4l2_codec2`。清单里只有 `c2.v4l2.avc.decoder` 和 `c2.v4l2.avc.encoder`。VP8、VP9、HEVC、AV1 和安全解码的属性是 false。

第 5 步还没做。2026-11-01 只写了 super：`work/phase4/super.codec.raw`，8589934592 字节，sha256 `c7700bf413be9e525d50696dd84966eb8711b8ca6a488fe37ee97f74fa864e5c`。读回和源一致，内核、pmOS_boot、metadata、misc、userdata 的前 1 MiB 没变。U 盘已卸载。这张镜像没有把播放交给 `c2.v4l2.avc.decoder`，原因和下一次要改的清单见下一节。VP9 仍是软解。

## 2026-11-01 硬件解码器没有被选中

同一条本地 1920×1080 H.264。文件名写着 4K，NuPlayer 报的是 1920×1080。MX 选“硬件解码”时，实际跑的是 `c2.android.avc.decoder`。`c2.v4l2.avc.decoder` 在清单里，`hw-accelerated` 是 1，AIDA64 能看到。logcat 里没有 `v4l2`，`/dev/video0` 没有进程占用，`android.hardware.media.c2-service-v4l2` 空闲。9919 帧里丢掉 1345 帧（13.6%）。三条 `oid.avc.decoder` 大约 81%+74%+53%，MX 的 `mx-pl-10` 大约 88%。画面是 YV12，SurfaceFlinger 客户端合成，`ROT_270`。

换成 MX 自己的软件解码之后，MediaCodec 客户端没了，解码在 MX 进程里：`mx-pl-10` 大约 97%，再加一条 `Thread-9` 和八条 `Thread-3`。整机 user 占用和上一轮接近，两簇 CPU 都在 1.99 GHz。画面改成 RGB565。少了 Android 软解那三条线程，也少了每帧 YV12 转 RGB，所以功耗从大约 8.0 W 降到 6.4 W。合成路径没变。

排位不是原因。`ComponentStore` 把 V4L2 组件写成 `0x80`（128），`c2.android.*` 的非音频组件默认 512。`MediaCodecList` 按排位从小到大排，128 本来就排在软件解码器前面。第一次实测时 dumpsys 也是 V4L2 在前。

挡住 MX 的是对齐。MX 的硬件解码走 NuPlayer，`MediaCodec::CreateByType` 先过 `MediaCodecList::codecHandlesFormat`，宽高必须是清单 `alignment` 的整数倍。清单写的是 `16x16`，1080 除以 16 余 8，`c2.v4l2.avc.decoder` 被跳过，下一个就是软件解码器。软件解码器和 mainline 示例都是 `2x2`。

性能点会再挡一层。解码器宏块预算 `489600` 就是 1920×1080@60，清单却写了 `performance-point-1920x1080` 的 `30-30`。相册的 ExoPlayer（media3 1.10）在 API 29 以上先看性能点，盖不住就判为不支持，把软件解码器排到前面。编码器宏块预算 `244800` 够 1920×1088@30 和 1280×720@60，清单只写了 720p30。

`feature-adaptive-playback` 在实机上是 0。空的 `<Feature>` 既没有 `required` 也没有 `optional`，解析结果就是不支持。软件解码器也是 0，不是这次没被选中的原因。分辨率中途变化还没测，不把它改成支持。

清单改为：解码器和编码器的 `rank` 都是 1024。解码器性能点改为 1920×1080 的 `60-60`。编码器改为 1920×1080 的 `30-30`，外加 1280×720 的 `60-60`。2026-11-01 只写了 super：`work/phase4/super.rank.raw`，8589934592 字节，sha256 `b068908621fd79df76195cb875262f6a822935b269ab8c89c08121e8c3033ba9`。读回和源一致，内核、pmOS_boot、metadata、misc、userdata 的前 1 MiB 没变。U 盘已卸载。Ctrl+U 之后实测没有打开 `/dev/video0`。`MediaCodecList` 按排位从小到大排，512 的 `c2.android.avc.decoder` 排在 1024 前面，MX 和相册都直接创建了软件解码器。同一条 1920×1080、59.94 fps 的 H.264：MX 这次软件解码的帧延迟平均 142 ms（90–237 ms）；相册的 Surface 在 2.08 秒里走了 126 帧，大约 60 fps，三条 `oid.avc.decoder` 合计约 190%，整机还有约 320% idle。硬件解码器这次没有跑起来，CPU 反块还没测到。同一轮里 MX 再播一条 1280×720 的 H.264，NuPlayer 仍是 `c2.android.avc.decoder`，1793 帧丢掉 5 帧（0.28%），`/dev/video0` 还是没人打开。这一轮是 1024 把 V4L2 排到了软件解码器后面。

## 2026-11-01 对齐修正

`etc/media_codecs_c2.xml` 再改一次：

- 去掉两条 `rank`，回到组件自己的 128，排在 512 的软件解码器和编码器前面。
- 解码器 `alignment` 改为 `2x2`，1920×1080 能过 `codecHandlesFormat`。组件的输出尺寸本来就是步长 1，从 2 到驱动报的上限。
- 解码器性能点保持 1920×1080 的 `60-60`，相册的 ExoPlayer 认得 1080p60 和 1080p30。
- 解码器码率上限从 20 Mbit/s 改为 62.5 Mbit/s，即 High profile level 4.2 的上限。
- 编码器保持 `16x16`。它还没有实机编过一帧，1080 高度的编码先不放开。

2026-11-01 只写了 super：`work/phase4/super.align.raw`，8589934592 字节，sha256 `0a199681108cc9f3feaa2fcf61319a61b3d6c8a5169b1b224ffd8ca8f2503d52`。读回和源一致，内核、pmOS_boot、metadata、misc、userdata 的前 1 MiB 没变。U 盘已卸载。Ctrl+U 之后，HW 模式选中了 `c2.v4l2.avc.decoder` 并打开了 `/dev/video0`。格式变化报的是 1920×1088、可见 1920×1080、fourcc `NV12`、至少 7 个输出缓冲。画面没有出来：解码线程在 `next_event` 里要一张 gralloc 缓冲做 `MM21` 到 NV12 的拷贝，`allocFrame` 发现 `mAvailableFrames` 是空的就返回失败，这一帧被丢掉。gralloc 缓冲是异步申请的，回调和这次解码在同一个任务队列上，要等当前这次 `decode()` 返回才能跑，所以一批帧里通常一张都拿不到。约 13 秒后 `bitstreamId=64` 的 work 已经不在，组件报 `C2_CORRUPTED`（14），flush 返回 -38，Surface 连接返回 -19。播放器停在这里。

HW+ 在第一个实例还活着的时候再创建 `c2.v4l2.avc.decoder`，被 `too many instances: 1` 拒绝（`error=12`），退回 `c2.android.avc.decoder`。所以 HW+ 能播，走的是软解。Surface 在 2.11 秒里走了 126 帧，平均约 60 fps，三条软解线程大约 83%+71%+50%，另外 `mx-pl-10` 约 88%。平均值到了 60，低处仍会顿。

能走硬件的范围是 H.264 Baseline/Main/High，level 不超过 4.2，最大 2048×1088。level 5.x 标记的 1080p 文件，ExoPlayer 会按 level 判为不支持，退回软解；NuPlayer 只看 profile。竖屏 1080×1920 超过高度上限，仍是软解。VP9、HEVC、AV1 仍是软解。

这条路径还没在 `MediaCodec` 里跑过。解码进驱动的 mmap 缓冲，cros-codecs 申请缓冲时没有带 `V4L2_MEMORY_FLAG_NON_COHERENT`，CPU 读的是不带缓存的映射。反块是 NEON，1080p60 若赶不上，先查这一步的读带宽。

## 2026-11-01 输出缓冲

卡死的原因是拷贝和 gralloc 申请不在同一拍。`next_event` 拿到一帧 `MM21` 之后立刻向 `allocFrame` 要一张客户缓冲。缓冲是 `VideoFramePool` 异步申请的，回调排在解码器自己的任务队列上，要等这次 `decode()` 返回才跑。队列空时 `allocFrame` 返回失败，旧代码把这一帧丢掉并结束事件循环，解码继续往下走，大约 64 个 bitstream 之后组件报 `C2_CORRUPTED`。

现在这一帧留在 FFI 里。`next_event` 改发 `CC_EVENT_NEED_OUTPUT`，C++ 停掉当前这次解码任务并去申请缓冲。缓冲到了，下一次任务先把留下的帧拷成 NV12，再继续读码流。没有缓冲时不再丢帧，也不再报错。

改动在 `system/cros-codecs/ffi/src/lib.rs`、`ffi/include/cros_codecs_ffi.h`（`patches/system_cros_codecs.patch`），以及 `external/v4l2_codec2/v4l2/StatelessV4L2Decoder.cpp`（`patches/external_v4l2_codec2.patch`）。播放是否顺还没看。帧能出来但 1080p60 仍一顿一顿的话，下一步看不带缓存的 mmap 反块，不先改 minigbm pitch，也不开 Vulkan。

2026-11-01 写入 super：`work/phase4/super.outbuf.raw`，8589934592 字节，sha256 `e195504c427deaf0bfb213e67b65449b2a4654f65f8dcc30697058110e707236`。读回和源一致，内核、pmOS_boot、metadata、misc、userdata 的前 1 MiB 没变。U 盘已卸载。播放是否顺还没看。

## 2026-11-01 快进

720p30 正常播放时硬件解码是开着的：`c2.v4l2.avc.decoder` 握着 `/dev/video0`，格式是 1280×768 编码、可见 1280×720、`NV12`。快进会把播放器停住。10:38:51 的 flush 把 bitstream 4006 到 4014 标成上一轮，随后 `DecodeComponent` 仍收到 4008 和 4006 的输出帧，work 已经不在，报 `C2_CORRUPTED`（14）。组件在 `FLUSHED` 状态进入错误，Surface 断开，MX 再 `start()` 时解码器已经是 `Released`。

原因是 H.264 的 `flush()` 会先把 DPB 里的帧排进事件队列。没有客户缓冲时这些帧被重新挂起（`CC_EVENT_NEED_OUTPUT`），`mDiscardOutput` 已经清掉之后才拷贝出来，送给已经被放弃的 work。现在 flush 排空队列时碰到 `CC_EVENT_NEED_OUTPUT` 就丢掉这一帧，不再等缓冲，也不再往外送。快进之后能不能接着播还没看。

2026-11-01 写入 super：`work/phase4/super.seek.raw`，8589934592 字节，sha256 `5392ce3b50a8962e7b4b3f0f1ce2d60566f95b8b899ccdd1755adfcea035a35f`。读回和源一致，内核、pmOS_boot、metadata、misc、userdata 的前 1 MiB 没变。U 盘已卸载。

同一条 1280×720、696 kb/s 的 H.264 在这版上仍由 `c2.v4l2.avc.decoder` 打开 `/dev/video0`。10:51:59 到 10:52:05 连续六次 flush（index 133、186、232、279、337、404），组件编号一直是 `#662`，没有 `C2_CORRUPTED`，也没有再创建软件解码器。用户确认快进可以接着播。

## 2026-11-01 1080p 快进后画面停住

同一版镜像上，1920×1080、59.94 fps 的 H.264 能选中 `c2.v4l2.avc.decoder`。10:55:27 的 `#561` 报了编码尺寸 1920×1088、可见 1920×1080、`NV12`。快进不再把组件打进 `C2_CORRUPTED`，10:56:25 的 flush 把 bitstream 1379 到 1384 标成上一轮。画面停在快进那一帧，音频继续。解码线程留在用户态，大约占满一颗核，Surface 不再换缓冲。

原因是同格式的 flush 没有关掉 V4L2 队列。1080p 还在飞的请求会在 flush 之后完成，解码线程一直在反块这些旧帧，新的 SPS 又以为队列还开着，于是后面的帧不再换成新画面。720p 的请求少、反块快，上一轮看不出来。

现在 flush 先丢掉已经进队列的旧帧，不再做 1080p 拷贝。下一次 `decode()` 等这些帧释放后把 V4L2 队列 stream off，下一条 SPS 即使参数没变也重新 `new_sequence`。对不上 work 的迟到帧直接丢掉，不再把组件打成错误。被放弃的输入标成 `FLAG_DROP_FRAME`，避免卡在输出队列最前面。解码任务每交出一帧就回到任务队列，flush 不用等整块输入解完。VAAPI 的 flush 路径不变。

2026-11-01 写入 super：`work/phase4/super.seek2.raw`，8589934592 字节，sha256 `98a68b5b38d2bcbb0bda8895c87ca38589fd9c63e4a1fb3bcd5a0188c0643d7e`。读回和源一致，内核、pmOS_boot、metadata、misc、userdata 的前 1 MiB 没变。U 盘已卸载。用户看过这版：1080p60 的现象和上一版一样。720p 的播放和快进是上一版确认过的。

## 2026-11-01 1080p30 放一段卡一段

同一版上正在播一条 1920×1080 的 H.264。硬件解码是开着的：`c2.v4l2.avc.decoder#907`，编码尺寸 1920×1088，可见 1920×1080，`NV12`，stride 1920。日志里没有 `C2_CORRUPTED`，也没有解码错误。

卡顿来自反块赶不上播放。`DecodeComponent` 一直在用户态，大约占一颗核的 78%。整机大约 230% user、430% idle，所以整机功耗看起来和亮屏待机差不多。10 秒里解码器交出 223 帧，其中 53 帧因为迟到被丢掉，平均大约 22 fps。一帧的 CPU 时间大约 35 ms，1080p30 每帧只有 33 ms。画面大部分时间按 33 ms 一帧在走，中间会空出大约 0.1 到 0.9 秒。音频时钟继续走，迟到超过 40 ms 的帧被整段丢掉，画面就停在上一帧，直到有一帧重新对上时间。720p 的像素大约是它的一半不到，同一条拷贝赶得上 30 fps。1080p60 每帧只有 16 ms，这条路径赶不上。下一步是让 MM21 的 mmap 读走缓存，而不是再改快进。

## 2026-11-01 捕获缓冲改走缓存

上一节的 35 ms 花在从不带缓存的映射里读 MM21。这块解码器的捕获队列已经允许缓存提示。申请捕获缓冲时带上 `V4L2_MEMORY_FLAG_NON_COHERENT`，mmap 是普通可缓存内存。驱动在把缓冲交回用户态之前作废这些缓存行，反块读到的是解码器刚写完的数据。码流那条队列仍走不带缓存的映射，数据量小，不改。没有关掉缓存同步，也没有重编内核。快进之后重新申请捕获缓冲时同样带这个标志。

改动在 `patches/external_v4l2r.patch` 和 `patches/system_cros_codecs.patch`。编 Gru 之前，`--reverse` 会把解码器这几份一起拿掉。

2026-11-01 写入 super：`work/phase4/super.cache.raw`，8589934592 字节，sha256 `730467bf11dcb9fb0d591e087710d8a7e43a7adf620ebb534aad993d9e5e8572`。读回和源一致，内核、pmOS_boot、metadata、misc、userdata 的前 1 MiB 没变。U 盘已卸载。1080p60 能不能连续播还没看。

同一版上，1280×720 的 H.264 由 `c2.v4l2.avc.decoder` 打开 `/dev/video0`，音频仍是 `c2.android.aac.decoder`。12:14:40 到 12:14:45 交出 303 帧，大约 60 fps，这 5 秒没有新的丢帧。整段 12979 帧里丢掉 42 帧（0.32%）。`DecodeComponent` 大约占一颗核的 20%，没有 `C2_CORRUPTED`。用户看这条是流畅的。1080p60 比上一版有改善，但还会放一段卡一段。

## 2026-11-01 1080p60 仍会放一段卡一段

同一版上正在播 1920×1080 的 H.264。硬件解码是开着的：`c2.v4l2.avc.decoder` 握着 `/dev/video0`，音频仍是 `c2.android.aac.decoder`。没有 `C2_CORRUPTED`。

12:16:53 到 12:17:03 这 10.1 秒交出 538 帧（大约 53 fps），其中 190 帧被丢掉，画面大约 35 fps。整段丢帧大约 34%。`DecodeComponent` 这 10 秒用了 5.15 秒 CPU，大约一颗核的一半，一帧的 CPU 时间大约 9.6 ms。墙上时间是 18.7 ms，比 60 fps 的 16.7 ms 多出来的大约 9 ms 不在 CPU 上。线程反复停在 `nanosleep`。

等画面的是 `DeviceHandle::sync`。捕获缓冲还没好就睡 2 ms，再不行睡 4 ms，然后 8 ms。解码器往往在某一次睡眠的中途就写完了，剩下的睡眠时间空等。反块本身大约 10 ms，已经进得了 16.7 ms。加上这段空等就变成 18.7 ms，慢慢落后，迟到超过 40 ms 的帧被整段丢掉，看起来就是放几秒卡一下。720p 的解码在第一次 2 ms 睡眠里就能完成，所以同一段等待赶得上 60 fps。下一步是把这段翻倍睡眠改成短轮询，而不是再改反块。

## 2026-11-01 等缓冲改成 poll

`DeviceHandle::sync` 和输出缓冲不够时的等待不再按 2、4、8 ms 往上睡。捕获缓冲用 `POLLIN`，输出缓冲用 `POLLOUT`，缓冲一就绪 `poll` 就返回。2 秒还没有缓冲才放弃。改动在 `patches/system_cros_codecs.patch`。编 Gru 之前，`--reverse` 会把这份和前面的解码补丁一起拿掉。

2026-11-01 写入 super：`work/phase4/super.poll.raw`，8589934592 字节，sha256 `bd1875c009697517ce82ec203353a6a53f7df4c053ca285efb9400fc5fafe3cb`。读回和源一致，内核、pmOS_boot、metadata、misc、userdata 的前 1 MiB 没变。U 盘已卸载。1080p60 能不能连续播还没看。

同一版上，1920×1080 的 H.264 由 `c2.v4l2.avc.decoder` 打开 `/dev/video0`，音频仍是 `c2.android.aac.decoder`。12:35:06 到 12:35:15 交出 559 帧，大约 61 fps，这 9.2 秒丢掉 2 帧。整段 8555 帧里丢掉 36 帧（0.42%）。`DecodeComponent` 大约占一颗核的 57%，一帧大约 9.3 ms，线程停在 `poll` 而不是 `nanosleep`。没有 `C2_CORRUPTED`。用户看这条是正常的，整机大约 5.5 W。
