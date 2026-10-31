#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/google/kukui

AB_OTA_UPDATER := false
TARGET_GRAPHICS := mesa
TARGET_GRAPHICS_VULKAN := none
TARGET_GRAPHICS_ALLOCATOR_HAL := minigbm-upstream
TARGET_MINIGBM_PLATFORM := generic
TARGET_DRM_HWCOMPOSER_VARIANT := aosp
TARGET_HAS_VIBRATOR := false
TARGET_SUPPORTS_USB_ACCESSORY_MODE := false
TARGET_USB_INIT_SCRIPT := none
TARGET_HOSTAPD_AND_WPA_SUPPLICANT_FORM := legacy
include device/mainline/common/optional/options.mk
SUPPORTS_INLINE_KERNEL_BUILDING := false

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base.mk)
$(call inherit-product, device/mainline/common/mainline_common.mk)

PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_SHIPPING_API_LEVEL := 36
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false
PRODUCT_CHARACTERISTICS := tablet
PRODUCT_PACKAGES += kukui-keep

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/etc/permissions/android.software.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.xml \
    frameworks/native/data/etc/android.software.cts.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.cts.xml \
    frameworks/native/data/etc/android.software.app_widgets.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.app_widgets.xml \
    frameworks/native/data/etc/android.software.backup.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.backup.xml \
    frameworks/native/data/etc/android.software.voice_recognizers.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.voice_recognizers.xml \
    frameworks/native/data/etc/android.software.print.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.print.xml \
    frameworks/native/data/etc/android.software.device_admin.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.device_admin.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.distinct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.multitouch.distinct.xml \
    $(LOCAL_PATH)/idc/hid-over-i2c_27C6_0E30.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/hid-over-i2c_27C6_0E30.idc \
    $(LOCAL_PATH)/fstab.kukui:$(TARGET_COPY_OUT_RAMDISK)/fstab.kukui \
    $(LOCAL_PATH)/fstab.kukui:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.kukui \
    $(LOCAL_PATH)/init.kukui.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/init.kukui.rc \
    $(LOCAL_PATH)/kukui-logcat.sh:$(TARGET_COPY_OUT_VENDOR)/bin/kukui-logcat.sh \
    $(LOCAL_PATH)/ueventd.kukui.rc:$(TARGET_COPY_OUT_RAMDISK)/ueventd.kukui.rc \
    $(LOCAL_PATH)/ueventd.kukui.rc:$(TARGET_COPY_OUT_VENDOR)/etc/ueventd.kukui.rc \
    $(LOCAL_PATH)/firmware/ath10k/QCA6174/hw3.0/board-2.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/ath10k/QCA6174/hw3.0/board-2.bin \
    $(LOCAL_PATH)/firmware/ath10k/QCA6174/hw3.0/firmware-sdio-6.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/ath10k/QCA6174/hw3.0/firmware-sdio-6.bin \
    $(LOCAL_PATH)/modules/rfkill.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/rfkill.ko \
    $(LOCAL_PATH)/modules/cfg80211.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/cfg80211.ko \
    $(LOCAL_PATH)/modules/libarc4.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/libarc4.ko \
    $(LOCAL_PATH)/modules/mac80211.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/mac80211.ko \
    $(LOCAL_PATH)/modules/ath.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/ath.ko \
    $(LOCAL_PATH)/modules/ath10k_core.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/ath10k_core.ko \
    $(LOCAL_PATH)/modules/ath10k_sdio.ko:$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules/ath10k_sdio.ko

PRODUCT_SYSTEM_PROPERTIES += \
    sys.use_memfd=true \
    persist.sys.disable_rescue=true

PRODUCT_PRODUCT_PROPERTIES += \
    ro.adb.secure=0 \
    ro.sf.lcd_density=240 \
    ro.surface_flinger.primary_display_orientation=ORIENTATION_270 \
    service.adb.tcp.port=5555 \
    debug.renderengine.backend=skiaglthreaded \
    debug.hwui.renderer=skiagl \
    ro.opengles.version=196609

PRODUCT_VENDOR_PROPERTIES += \
    vendor.hwc.drm.device=/dev/dri/card0 \
    vendor.hwc.drm.internal_display_names=DSI-1 \
    vendor.usb.configfs=0 \
    vendor.minigbm.device=/dev/dri/card0
