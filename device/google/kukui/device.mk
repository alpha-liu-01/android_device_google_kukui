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
    $(LOCAL_PATH)/fstab.kukui:$(TARGET_COPY_OUT_RAMDISK)/fstab.kukui \
    $(LOCAL_PATH)/fstab.kukui:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.kukui \
    $(LOCAL_PATH)/init.kukui.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/init.kukui.rc \
    $(LOCAL_PATH)/kukui-logcat.sh:$(TARGET_COPY_OUT_VENDOR)/bin/kukui-logcat.sh \
    $(LOCAL_PATH)/ueventd.kukui.rc:$(TARGET_COPY_OUT_RAMDISK)/ueventd.kukui.rc \
    $(LOCAL_PATH)/ueventd.kukui.rc:$(TARGET_COPY_OUT_VENDOR)/etc/ueventd.kukui.rc

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
