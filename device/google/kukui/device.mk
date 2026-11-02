#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/google/kukui

# Static overlay. PRODUCT_ENFORCE_RRO_TARGETS turns this into a runtime overlay.
DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay

AB_OTA_UPDATER := false
TARGET_GRAPHICS := mesa
TARGET_GRAPHICS_VULKAN := mesa
# Before mainline_common.mk, which pulls in optional/v4l2_codec2/product.mk.
# The example configuration advertises VP8, VP9 and secure decoders this chip
# does not enumerate. Kukui ships its own media_codecs_c2.xml.
TARGET_MEDIA_C2_HAL := v4l2_codec2
TARGET_V4L2_CODEC2_USE_EXAMPLE_CONFIGURATION := false
TARGET_GRAPHICS_ALLOCATOR_HAL := minigbm-upstream
TARGET_MINIGBM_PLATFORM := generic
TARGET_DRM_HWCOMPOSER_VARIANT := aosp
TARGET_HAS_VIBRATOR := false
TARGET_SUPPORTS_USB_ACCESSORY_MODE := false
TARGET_USB_INIT_SCRIPT := none
TARGET_HOSTAPD_AND_WPA_SUPPLICANT_FORM := legacy
# Set before options.mk. default-aidl otherwise pulls the cuttlefish policy.
TARGET_AUDIO_HAL := default-aidl
TARGET_AUDIO_POLICY := kukui
# Kukui edits to hardware/interfaces live in this repo's patches/.
# Without them, lunch still builds, but the speaker opens card 0.
ifeq ($(wildcard $(LOCAL_PATH)/../../../hardware/interfaces/audio/aidl/default/include/core-impl/KukuiMixer.h),)
$(error Kukui audio patch is not applied. Run patches/apply-patches.sh on the LineageOS tree before building kukui.)
endif
include device/mainline/common/optional/options.mk
SUPPORTS_INLINE_KERNEL_BUILDING := false

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base.mk)
$(call inherit-product, device/mainline/common/mainline_common.mk)

PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_SHIPPING_API_LEVEL := 36
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false
PRODUCT_CHARACTERISTICS := tablet
# EC accelerometer subhal. Sources are hal/sensors in this tree.
PRODUCT_PACKAGES += \
    kukui-keep \
    KukuiInstall \
    kukui-installd \
    KukuiUsbSuspend \
    android.hardware.sensors-service.multihal \
    android.hardware.sensors@2.1-kukui-subhal \
    android.hardware.camera.provider-service.lineage \
    camera.libcamera \
    libcamera \
    libcamera-base \
    ipa_soft_simple \
    libcamera_soft_ipa_proxy

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/etc/permissions/android.software.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.xml \
    frameworks/native/data/etc/android.software.cts.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.cts.xml \
    frameworks/native/data/etc/android.software.app_widgets.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.app_widgets.xml \
    frameworks/native/data/etc/android.software.backup.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.backup.xml \
    frameworks/native/data/etc/android.software.voice_recognizers.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.voice_recognizers.xml \
    frameworks/native/data/etc/android.software.print.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.print.xml \
    frameworks/native/data/etc/android.software.device_admin.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.device_admin.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.distinct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.multitouch.distinct.xml \
    frameworks/native/data/etc/android.hardware.vulkan.version-1_0_3.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.version.xml \
    frameworks/native/data/etc/android.hardware.vulkan.level-0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.level.xml \
    frameworks/native/data/etc/android.hardware.vulkan.compute-0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.compute.xml \
    $(LOCAL_PATH)/idc/hid-over-i2c_27C6_0E30.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/hid-over-i2c_27C6_0E30.idc \
    $(LOCAL_PATH)/idc/hid-over-i2c_27C6_0E30_Stylus.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/hid-over-i2c_27C6_0E30_Stylus.idc \
    $(LOCAL_PATH)/keylayout/Vendor_18d1_Product_503c.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/Vendor_18d1_Product_503c.kl \
    $(LOCAL_PATH)/fstab.kukui:$(TARGET_COPY_OUT_RAMDISK)/fstab.kukui \
    $(LOCAL_PATH)/fstab.kukui:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.kukui \
    $(LOCAL_PATH)/init.kukui.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/init.kukui.rc \
    $(LOCAL_PATH)/installer/kukui-install.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/kukui-install.rc \
    $(LOCAL_PATH)/kukui-logcat.sh:$(TARGET_COPY_OUT_VENDOR)/bin/kukui-logcat.sh \
    $(LOCAL_PATH)/kukui-usb-suspend.sh:$(TARGET_COPY_OUT_VENDOR)/bin/kukui-usb-suspend.sh \
    $(LOCAL_PATH)/kukui-wifi-reprobe.sh:$(TARGET_COPY_OUT_VENDOR)/bin/kukui-wifi-reprobe.sh \
    $(LOCAL_PATH)/ueventd.kukui.rc:$(TARGET_COPY_OUT_RAMDISK)/ueventd.kukui.rc \
    $(LOCAL_PATH)/ueventd.kukui.rc:$(TARGET_COPY_OUT_VENDOR)/etc/ueventd.kukui.rc \
    $(LOCAL_PATH)/wpa_supplicant.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant.conf \
    $(LOCAL_PATH)/firmware/ath10k/QCA6174/hw3.0/board-2.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/ath10k/QCA6174/hw3.0/board-2.bin \
    $(LOCAL_PATH)/firmware/ath10k/QCA6174/hw3.0/firmware-sdio-6.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/ath10k/QCA6174/hw3.0/firmware-sdio-6.bin \
    $(LOCAL_PATH)/firmware/qca/nvm_00440302_i2s_eu.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/qca/nvm_00440302_i2s_eu.bin \
    $(LOCAL_PATH)/firmware/qca/rampatch_00440302.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/qca/rampatch_00440302.bin \
    $(LOCAL_PATH)/firmware/mediatek/mt8183/scp.img:$(TARGET_COPY_OUT_VENDOR)/firmware/mediatek/mt8183/scp.img \
    $(LOCAL_PATH)/etc/media_codecs_c2.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_c2.xml \
    $(LOCAL_PATH)/etc/media_profiles_V1_0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_V1_0.xml \
    frameworks/native/data/etc/android.hardware.camera.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.xml \
    frameworks/native/data/etc/android.hardware.camera.front.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.front.xml \
    $(LOCAL_PATH)/etc/libcamera/configuration.yaml:$(TARGET_COPY_OUT_VENDOR)/etc/libcamera/configuration.yaml \
    $(LOCAL_PATH)/etc/libcamera/camera_hal.yaml:$(TARGET_COPY_OUT_VENDOR)/etc/libcamera/camera_hal.yaml \
    $(LOCAL_PATH)/etc/libcamera/ipa/simple/ov8856.yaml:$(TARGET_COPY_OUT_VENDOR)/share/libcamera/ipa/simple/ov8856.yaml \
    $(LOCAL_PATH)/etc/libcamera/ipa/simple/ov02a10.yaml:$(TARGET_COPY_OUT_VENDOR)/share/libcamera/ipa/simple/ov02a10.yaml \
    $(LOCAL_PATH)/etc/libcamera/ipa/simple/uncalibrated.yaml:$(TARGET_COPY_OUT_VENDOR)/share/libcamera/ipa/simple/uncalibrated.yaml \
    $(LOCAL_PATH)/modules/rfkill.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/rfkill.ko \
    $(LOCAL_PATH)/modules/cfg80211.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/cfg80211.ko \
    $(LOCAL_PATH)/modules/libarc4.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/libarc4.ko \
    $(LOCAL_PATH)/modules/mac80211.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mac80211.ko \
    $(LOCAL_PATH)/modules/ath.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/ath.ko \
    $(LOCAL_PATH)/modules/ath10k_core.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/ath10k_core.ko \
    $(LOCAL_PATH)/modules/ath10k_sdio.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/ath10k_sdio.ko \
    $(LOCAL_PATH)/modules/sbs-battery.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/sbs-battery.ko \
    $(LOCAL_PATH)/modules/cros_usbpd-charger.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/cros_usbpd-charger.ko \
    $(LOCAL_PATH)/modules/ecc.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/ecc.ko \
    $(LOCAL_PATH)/modules/ecdh_generic.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/ecdh_generic.ko \
    $(LOCAL_PATH)/modules/bluetooth.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/bluetooth.ko \
    $(LOCAL_PATH)/modules/btqca.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/btqca.ko \
    $(LOCAL_PATH)/modules/btbcm.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/btbcm.ko \
    $(LOCAL_PATH)/modules/btrtl.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/btrtl.ko \
    $(LOCAL_PATH)/modules/hci_uart.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/hci_uart.ko \
    $(LOCAL_PATH)/modules/hidp.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/hidp.ko \
    $(LOCAL_PATH)/modules/rfcomm.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/rfcomm.ko \
    $(LOCAL_PATH)/modules/uhid.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/uhid.ko \
    $(LOCAL_PATH)/modules/kfifo_buf.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/kfifo_buf.ko \
    $(LOCAL_PATH)/modules/industrialio-triggered-buffer.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/industrialio-triggered-buffer.ko \
    $(LOCAL_PATH)/modules/cros-ec-sensors-core.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/cros-ec-sensors-core.ko \
    $(LOCAL_PATH)/modules/cros_ec_sensors.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/cros_ec_sensors.ko \
    $(LOCAL_PATH)/modules/cros_ec_light_prox.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/cros_ec_light_prox.ko \
    $(LOCAL_PATH)/modules/mtk_wdt.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mtk_wdt.ko \
    $(LOCAL_PATH)/modules/mc.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mc.ko \
    $(LOCAL_PATH)/modules/mtk_scp_ipi.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mtk_scp_ipi.ko \
    $(LOCAL_PATH)/modules/mtk_rpmsg.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mtk_rpmsg.ko \
    $(LOCAL_PATH)/modules/mtk_scp.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mtk_scp.ko \
    $(LOCAL_PATH)/modules/mtk-vpu.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mtk-vpu.ko \
    $(LOCAL_PATH)/modules/videobuf2-common.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/videobuf2-common.ko \
    $(LOCAL_PATH)/modules/videobuf2-memops.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/videobuf2-memops.ko \
    $(LOCAL_PATH)/modules/videobuf2-dma-contig.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/videobuf2-dma-contig.ko \
    $(LOCAL_PATH)/modules/videodev.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/videodev.ko \
    $(LOCAL_PATH)/modules/v4l2-async.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/v4l2-async.ko \
    $(LOCAL_PATH)/modules/v4l2-fwnode.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/v4l2-fwnode.ko \
    $(LOCAL_PATH)/modules/phy-mtk-mipi-csi-0-5.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/phy-mtk-mipi-csi-0-5.ko \
    $(LOCAL_PATH)/modules/mtk-seninf.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mtk-seninf.ko \
    $(LOCAL_PATH)/modules/mtk-camsv.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mtk-camsv.ko \
    $(LOCAL_PATH)/modules/dw9768.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/dw9768.ko \
    $(LOCAL_PATH)/modules/ov8856.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/ov8856.ko \
    $(LOCAL_PATH)/modules/ov02a10.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/ov02a10.ko \
    $(LOCAL_PATH)/modules/videobuf2-v4l2.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/videobuf2-v4l2.ko \
    $(LOCAL_PATH)/modules/v4l2-mem2mem.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/v4l2-mem2mem.ko \
    $(LOCAL_PATH)/modules/v4l2-h264.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/v4l2-h264.ko \
    $(LOCAL_PATH)/modules/v4l2-vp9.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/v4l2-vp9.ko \
    $(LOCAL_PATH)/modules/mtk-vcodec-common.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mtk-vcodec-common.ko \
    $(LOCAL_PATH)/modules/mtk-vcodec-dbgfs.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mtk-vcodec-dbgfs.ko \
    $(LOCAL_PATH)/modules/mtk-vcodec-dec.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mtk-vcodec-dec.ko \
    $(LOCAL_PATH)/modules/mtk-vcodec-enc.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mtk-vcodec-enc.ko \
    $(LOCAL_PATH)/modules/snd-seq-device.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-seq-device.ko \
    $(LOCAL_PATH)/modules/snd-rawmidi.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-rawmidi.ko \
    $(LOCAL_PATH)/modules/snd-ump.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-ump.ko \
    $(LOCAL_PATH)/modules/snd-hwdep.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-hwdep.ko \
    $(LOCAL_PATH)/modules/snd-usbmidi-lib.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-usbmidi-lib.ko \
    $(LOCAL_PATH)/modules/snd-usb-audio.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-usb-audio.ko \
    $(LOCAL_PATH)/modules/snd-soc-mtk-common.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-soc-mtk-common.ko \
    $(LOCAL_PATH)/modules/snd-soc-mt8183-afe.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-soc-mt8183-afe.ko \
    $(LOCAL_PATH)/modules/snd-soc-mt6358.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-soc-mt6358.ko \
    $(LOCAL_PATH)/modules/snd-soc-max98357a.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-soc-max98357a.ko \
    $(LOCAL_PATH)/modules/snd-soc-ts3a227e.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-soc-ts3a227e.ko \
    $(LOCAL_PATH)/modules/snd-soc-bt-sco.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/snd-soc-bt-sco.ko \
    $(LOCAL_PATH)/modules/mt8183-mt6358-ts3a227-max98357.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mt8183-mt6358-ts3a227-max98357.ko \
    $(LOCAL_PATH)/etc/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/usb_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/usb_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/r_submix_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/r_submix_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/bluetooth_audio_policy_configuration_7_0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth_audio_policy_configuration_7_0.xml \
    frameworks/av/services/audiopolicy/config/audio_policy_volumes.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_volumes.xml \
    frameworks/av/services/audiopolicy/config/default_volume_tables.xml:$(TARGET_COPY_OUT_VENDOR)/etc/default_volume_tables.xml \
    frameworks/native/data/etc/android.hardware.audio.output.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.audio.output.xml \
    $(LOCAL_PATH)/etc/permissions/android.hardware.microphone.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.microphone.xml \
    $(LOCAL_PATH)/etc/sensors/hals.conf:$(TARGET_COPY_OUT_VENDOR)/etc/sensors/hals.conf \
    $(LOCAL_PATH)/etc/sensors/sensor_hal_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/sensors/sensor_hal_configuration.xml \
    frameworks/native/data/etc/android.hardware.sensor.accelerometer.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.accelerometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.gyroscope.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.gyroscope.xml \
    $(LOCAL_PATH)/modules/modules.load:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/modules.load \
    $(LOCAL_PATH)/modules/modules.dep:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/modules.dep \
    $(LOCAL_PATH)/modules/modules.alias:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/modules.alias \
    $(LOCAL_PATH)/modules/modules.softdep:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/modules.softdep

PRODUCT_SYSTEM_PROPERTIES += \
    sys.use_memfd=true \
    persist.sys.disable_rescue=true \
    mmd.zram.enabled=true \
    mmd.zram.comp_algorithm=zstd \
    mmd.zram.size=50%

PRODUCT_PRODUCT_PROPERTIES += \
    ro.adb.secure=0 \
    ro.sf.lcd_density=240 \
    ro.surface_flinger.primary_display_orientation=ORIENTATION_270 \
    service.adb.tcp.port=5555 \
    debug.renderengine.backend=skiaglthreaded \
    debug.hwui.renderer=skiagl \
    ro.opengles.version=196609 \
    bluetooth.device.class_of_device=90,2,12 \
    bluetooth.le.disable_apcf_extended_features=1 \
    persist.bluetooth.a2dp_aac.vbr_supported=true \
    bluetooth.profile.asha.central.enabled=true \
    bluetooth.profile.a2dp.source.enabled=true \
    bluetooth.profile.avrcp.target.enabled=true \
    bluetooth.profile.gatt.enabled=true \
    bluetooth.profile.hfp.ag.enabled=true \
    bluetooth.profile.hid.device.enabled=true \
    bluetooth.profile.hid.host.enabled=true \
    bluetooth.profile.map.server.enabled=true \
    bluetooth.profile.opp.enabled=true \
    bluetooth.profile.pan.nap.enabled=true \
    bluetooth.profile.pan.panu.enabled=true \
    bluetooth.profile.pbap.server.enabled=true \
    bluetooth.profile.sap.server.enabled=true \
    bluetooth.profile.bap.broadcast.assist.enabled=false \
    bluetooth.profile.bap.unicast.client.enabled=false \
    bluetooth.profile.bas.client.enabled=false \
    bluetooth.profile.ccp.server.enabled=false \
    bluetooth.profile.csip.set_coordinator.enabled=false \
    bluetooth.profile.hap.client.enabled=false \
    bluetooth.profile.vcp.controller.enabled=false

PRODUCT_VENDOR_PROPERTIES += \
    vendor.hwc.drm.device=/dev/dri/card0 \
    vendor.hwc.drm.internal_display_names=DSI-1 \
    vendor.usb.configfs=0 \
    vendor.minigbm.device=/dev/dri/card0 \
    ro.vendor.audio.route=kukui \
    ro.vendor.audio.tinyalsa.analog_device=0 \
    ro.vendor.v4l2_codec2.decoder.supported.h264=true \
    ro.vendor.v4l2_codec2.decoder.supported.vp8=false \
    ro.vendor.v4l2_codec2.decoder.supported.vp9=false \
    ro.vendor.v4l2_codec2.decoder.supported.hevc=false \
    ro.vendor.v4l2_codec2.decoder.supported.av1=false \
    ro.vendor.v4l2_codec2.decoder.supported.h264.secure=false \
    ro.vendor.v4l2_codec2.encoder.supported.h264=true \
    ro.vendor.v4l2_codec2.encoder.supported.vp8=false \
    ro.vendor.v4l2_codec2.encoder.supported.vp9=false \
    ro.vendor.v4l2_codec2.decode_concurrent_instances=1 \
    ro.vendor.v4l2_codec2.encode_concurrent_instances=1 \
    debug.stagefright.c2-poolmask=0xf50000 \
    ro.hardware.camera=libcamera \
    ro.hardware.vulkan=panfrost
