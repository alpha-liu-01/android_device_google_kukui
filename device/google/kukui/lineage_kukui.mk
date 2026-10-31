#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

$(call inherit-product, vendor/lineage/config/common_full_tablet_wifionly.mk)
$(call inherit-product, device/google/kukui/device.mk)

PRODUCT_NAME := lineage_kukui
PRODUCT_DEVICE := kukui
PRODUCT_BRAND := Android
PRODUCT_MODEL := Lenovo IdeaPad Duet
PRODUCT_MANUFACTURER := Google

TARGET_SCREEN_WIDTH := 1920
TARGET_SCREEN_HEIGHT := 1200
TARGET_SCREEN_DENSITY := 240
