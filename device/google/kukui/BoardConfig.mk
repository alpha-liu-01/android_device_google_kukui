#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/google/kukui
MAINLINE_COMMON_PATH := device/mainline/common

AB_OTA_UPDATER := false
TARGET_GRAPHICS := mesa
TARGET_GRAPHICS_VULKAN := mesa
TARGET_GRAPHICS_ALLOCATOR_HAL := minigbm-upstream
TARGET_MINIGBM_PLATFORM := generic
BOARD_MESA3D_GALLIUM_DRIVERS := panfrost
TARGET_HAS_VIBRATOR := false
TARGET_SUPPORTS_USB_ACCESSORY_MODE := false
TARGET_USB_INIT_SCRIPT := none
include $(MAINLINE_COMMON_PATH)/optional/options.mk
SUPPORTS_INLINE_KERNEL_BUILDING := false

include $(MAINLINE_COMMON_PATH)/BoardConfigMainlineCommon.mk

BOARD_MESA3D_GALLIUM_DRIVERS := panfrost
BOARD_MESA3D_VULKAN_DRIVERS := panfrost

TARGET_NO_KERNEL := true
TARGET_KERNEL_MIXED_MODE := false

TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := generic
TARGET_SUPPORTS_64_BIT_APPS := true

TARGET_BOOTLOADER_BOARD_NAME := kukui
TARGET_BOARD_PLATFORM := kukui
TARGET_NO_RADIOIMAGE := true
TARGET_NO_BOOTLOADER := true

BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# The block device's closest platform node is under soc/, not the bare
# xHCI name. init only creates /dev/block/by-name for an exact match.
# selinux must come before bpf. bpf's procattr hook returns EINVAL and
# is the first match, so setexeccon never reaches SELinux.
BOARD_KERNEL_CMDLINE := lsm=landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,bpf console=tty0 loglevel=7 deferred_probe_timeout=30 androidboot.selinux=permissive androidboot.hardware=kukui androidboot.boot_devices=soc/11201000.usb/11200000.usb printk.devkmsg=on
BOARD_BOOTCONFIG :=

DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/fstab.kukui

BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs
TARGET_USERIMAGES_USE_F2FS := true
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_F2FS_BLOCKSIZE := 4096
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm
TARGET_COPY_OUT_SYSTEM_DLKM := system_dlkm
BOARD_USES_METADATA_PARTITION := true
BOARD_FLASH_BLOCK_SIZE := 4096

BOARD_BUILD_SUPER_IMAGE_BY_DEFAULT := true
BOARD_SUPER_PARTITION_METADATA_DEVICE := super
BOARD_SUPER_PARTITION_SIZE := 8589934592
BOARD_KUKUI_DYNAMIC_PARTITIONS_SIZE := 8585740288
BOARD_SUPER_PARTITION_GROUPS := kukui_dynamic_partitions
BOARD_KUKUI_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor system_ext product system_dlkm vendor_dlkm

BOARD_USERDATAIMAGE_PARTITION_SIZE := 4294967296

TARGET_SCREEN_WIDTH := 1920
TARGET_SCREEN_HEIGHT := 1200
TARGET_SCREEN_DENSITY := 240

# Product makefiles are imported before this file, and the minigbm product
# makefile copies the trunk_staging flag in. Set it again here so the vendor
# mapper is not deleted by the APEX.
$(call soong_config_set_bool,minigbm_upstream,RELEASE_SM_OPEN_DECLARED_PASSTHROUGH_HAL,false)

BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor

# libksud.so is executed by the manager. PRODUCT_COPY_FILES installs it 0644,
# and system_ext is erofs, so the mode has to be set here.
TARGET_FS_CONFIG_GEN += $(DEVICE_PATH)/config.fs
