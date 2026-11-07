# Goodix 27C6:0E31 on i2c-0 address 0x5d. Krane sku0 has this part,
# sku176 has 27C6:0E30. The kernel names this node
# "hid-over-i2c 27C6:0E31". The Stylus and UNKNOWN nodes from the same
# chip use different names and do not pick up this file.
device.internal = 1
touch.deviceType = touchScreen
# Same raw axes as 0E30 (x 0..7200 on the short edge, y 0..11520 on the
# long edge). Without this file the sku0 digitizer is mapped at
# Rotation0 against the landscape display.
touch.orientation = ORIENTATION_270
