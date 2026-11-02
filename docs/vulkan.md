# 启用 Vulkan

2026-11-01。给游戏、模拟器和以后的 GPU 计算用。这一篇只打开驱动，不把桌面合成改成 Vulkan，也不在这一步改取景框。

GPU 是 Mali-G72 MP3，内核驱动 panfrost 已经在 `/dev/dri/card1` 和 `/dev/dri/renderD128`。节点权限 `0666`，标签 `gpu_device`。最高 800 MHz，空闲时停在 300 MHz。合成用的 OpenGL ES 走 Mesa Panfrost，`libGLESv2_mesa.so` 已在 vendor 里。Vulkan ICD 原来没有：`TARGET_GRAPHICS_VULKAN` 是 `none`，`BOARD_MESA3D_VULKAN_DRIVERS` 是空的。

树里的 Mesa 是 `external/mesa` 25.3.3。panvk 含 Bifrost（第 6、7 代，G72 是第 6 代）的 compute 和绘制。这颗芯片上报的 API 版本是 Vulkan 1.0，一致性版本是 0.0.0.0。第 10 代及以后才报 1.4。所以特性不能写成 1.3 或 level 1。

## 步骤

1. 不改内核，不改内核版本字符串。panfrost 已经编进正在跑的内核。
2. 合成器继续用 GLES。`init.kukui.rc` 里的 `debug.hwui.renderer=skiagl` 和 `debug.renderengine.backend=skiaglthreaded` 保持。这颗 GPU 画窗口阴影大约 24 毫秒，60 Hz 面板会掉到一半。把桌面改成 skiavk 会更糟，也不是游戏要的那条路径。
3. `BoardConfig.mk` 和 `device.mk` 在引入 `options.mk` 之前把 `TARGET_GRAPHICS_VULKAN` 设成 `mesa`。`BOARD_MESA3D_VULKAN_DRIVERS := panfrost`。产品是 `core_64_bit_only`，只出 64 位的 `vulkan.panfrost.so`。32 位模拟器看不到这套驱动，不为此把系统改成双 ABI。
4. `ro.hardware.vulkan=panfrost`。加载器先读这个属性，再退回 `ro.board.platform`（kukui）。库装到 `/vendor/lib64/hw/vulkan.panfrost.so`。正在跑的系统上这个属性还是空的，所以旧系统不会自己去加载它。
5. 特性 XML 用 1.0.3（`4194307`）、level 0、compute 0。level 1 要等探针读出实际特性，对照 CDD 再提高。报高了，游戏会按不存在的功能来创建 device。
6. 应用打开渲染节点：DAC 已经是 `0666`。平台策略里 `appdomain`（隔离应用除外）可以读写 `gpu_device`。SELinux 仍是 permissive。enforcing 时这条不用另写，除非实机 denial 指向别的类型。
7. 只编译 `vulkan.panfrost`。不写 U 盘，不重启平板。新的 super 要等这块库进 vendor 之后另做，文件名不要盖住 `super.camera-hal.raw`。
8. Mesa 对 Bifrost（第 6、7 代）直接拒绝枚举，除非进程里有 `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`。这个变量写在 `init.kukui.rc` 的 `early-init`，下一次启动后 zygote 里的应用都能继承。不改 Mesa 源码把检查删掉。
9. 库编出来之后，用系统的 `libvulkan.so` 加载它，创建 instance 和 device。测完把临时挂载卸掉，不留在 `/vendor/lib64/hw/`。
10. 下一次人工测试：新 super 写入并 Ctrl+U 之后，用一个 64 位 Vulkan 程序看能否出画面。桌面、相机取景仍应是现在的 GLES 路径。32 位应用不在这次范围内。

取景框的 GPU 去马赛克等第 8 步确认 device 能创建之后再做。那是计算着色器，不是把系统合成改成 Vulkan。

## 这次改了什么

`BoardConfig.mk`、`device.mk` 按第 3 到第 5 步写了。`init.kukui.rc` 增加了上面的环境变量，合成器的 GLES 属性没改。`vulkan.panfrost` 已编出，在 `out/target/product/kukui/vendor/lib64/hw/vulkan.panfrost.so`。特性 XML、`ro.hardware.vulkan` 和这个环境变量都要等下一次启动才生效。

2026-11-01 在正在跑的系统上，把库临时放成加载器会找的 `vulkan.kukui.so`（这台现在的 `ro.hardware.vulkan` 是空的，会退回平台名 kukui），用系统加载器创建了 instance 和 device，然后卸掉挂载。读到的设备是 Mali-G72，API 1.0.328，厂商 `0x13b5`，设备号 `0x62210000`。唯一队列同时带图形、计算和传输，`vkCreateDevice` 返回成功。没有这个环境变量时，同一块库创建 instance 成功，但物理设备数是 0。直接 `dlopen` 而不走系统加载器时，会卡在 `/dev/vndbinder`，因为这台没有 vndservicemanager。应用走系统加载器，不会走那条。

2026-11-01 把这张 super 写成 `work/phase4/super.vk.raw`，8589934592 字节，sha256 `a4ab55590721edc89fc5440d7ec328047e47d027b71315e49791d6219eb75ed7`。只写入 SanDisk（序列号 `000000002959`）的 super。读回一致。内核槽开头 1 MiB 仍是 `1ebedee8e582b76f78dd6f3b7468ca3d4a1c5164c222ce11aacf66d7df9ed545`。pmOS_boot、metadata、misc、userdata 的开头 1 MiB 没有变。卡已卸载。eMMC 没写。

Ctrl+U 之后 Geekbench 6 的 GPU 测试能认出 Mali-G72，开始大约 3 秒就退出。tombstone 里的异常是 `failed to find suitable memory type`。Geekbench 先按 `HOST_VISIBLE | HOST_CACHED`（0xa）找内存类型，找不到就抛异常，后面的回退不会执行。panvk 原来只公布一种类型，标志是 `DEVICE_LOCAL | HOST_VISIBLE | HOST_COHERENT`（0x7），没有 `HOST_CACHED`。3DMark 当次没有 tombstone，进程里只有兼容性界面和主界面，随后应用已被卸掉。特性仍是 level 0。

Mesa 的 `panvk_GetPhysicalDeviceMemoryProperties2` 现在公布第二种类型，在原来的标志上加上 `HOST_CACHED`。缓冲、图像和 dma-buf 的 `memoryTypeBits` 改成同时包含这两种。合成器仍是 GLES。探针读到两种类型（0x7 和 0xf），缓冲的 typeBits 是 0x3，按 Geekbench 的 0xa 和 0xb 分配并映射都成功。扩展里有 `VK_KHR_swapchain` 和 `VK_ANDROID_external_memory_android_hardware_buffer`。

补上 `HOST_CACHED` 之后，Geekbench 不再闪退，但进度停在 0%，整机功耗约 3.2 W。内核报 `gpu sched timeout, js=0, status=0x8`，`head==tail`。`status=0x8` 是作业槽仍在 ACTIVE，不是故障码。这颗内核的作业超时是 500 毫秒。一次很大的计算派发还在跑就被复位，显示用的片段作业也跟着被拆掉，所以界面卡住，取消要等很久。短的计算（单线程存储、64 宽工作组、屏障、int8、点积）都在超时内完成。

Bifrost 的直接计算派发现在按网格切开。每个作业大约不超过 128 个工作组，并且线程数大约不超过 8192。屏障只在一个工作组内，切开网格是合法的。`gl_NumWorkGroups` 仍是原来的整次派发；`gl_WorkGroupID` 加上这一段的起点。300 宽、本地大小为 1 的探针读到 id 0、128、299，工作组数是 300。间接派发没有切。

正在跑的系统上，这个库（sha256 `9b92d5be4524d0ee7e95d224dd1e27472139d8a3f9205512a29bea675495c00f`）bind 在 `/vendor/lib64/hw/vulkan.panfrost.so`。整次 Geekbench GPU 跑完，得分 349。镜像里没有 `PANVK_DEBUG`。`PAN_I_WANT_A_BROKEN_VULKAN_DRIVER` 还在，没有它 Bifrost 的物理设备数是 0，它不是性能开关。349 分来自上面那刀切法：本地大小 256 时，一次 9216 个工作组的派发被拆成大约 288 个作业，每个作业都做一遍缓存刷新。ChromeOS 上同一台 Kukui（带着 ARCVM）的 1109 分只作对照。3DMark 还没再装。

2026-11-01 把切分上限改成最多 16384 个工作组、并且线程数不超过 4 MiB。一次 9216×256 的派发因此合成一个作业。合成器仍是 GLES。这张 super 写成 `work/phase4/super.vk2.raw`，8589934592 字节，sha256 `6f84e6c6bbc0fdc1757b95099dfd8a8326d3b6c060d31eadc741824b1303bed4`。只写入 SanDisk（序列号 `000000002959`）的 super。读回一致。内核槽开头 1 MiB 仍是 `1ebedee8e582b76f78dd6f3b7468ca3d4a1c5164c222ce11aacf66d7df9ed545`。Ctrl+U 之后 Geekbench GPU 是 493 分。3DMark Sling Shot Extreme Vulkan 图形分 1695。

再放宽之后分数没有上去。Background Blur 里比 16384 大的派发主要是三种：`24192×1` 本地大小 32、`30×1080` 本地大小 64（32400 组）、`60×1080` 本地大小 32（64800 组）。上限放到 100 万组、64 Mi 线程时，64800 组合成一个作业，十几秒就 `gpu sched timeout`（`status=0x8`，`head==tail`）。改成 32768 组、8 Mi 线程后，64800 组拆成两个作业，24192 组合成一个。这版库（sha256 `ac5a8727be9a481f6057bd4bc0e2ba37c99609b8d7d568dae62880a5546b1908`）在正在跑的系统上整次 Geekbench 仍是 493 分，期间内核记了 15 次同样的超时。这些作业复位之后那一项等于重来，所以总分不动。16384 组、4 MiB 线程留作上限。Geekbench 的计算着色器只有默认、`int32`、`int8` 三份，int8、点积和 16 位存储本来就开着，没有另一条没启用的着色器能补上和闭源驱动的差距。这版没有写进镜像。
