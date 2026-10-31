# Goodix 27C6:0E30 on i2c-0 address 0x5d. The kernel names this node
# "hid-over-i2c 27C6:0E30". The Stylus and UNKNOWN nodes from the same
# chip use different names and do not pick up this file.
device.internal = 1
touch.deviceType = touchScreen
# Panel scanout is portrait and the display is already rotated 270.
# With orientation 0, a finger moving from the right edge toward the
# left edge is delivered as a top-to-bottom swipe. 270 cancels that.
touch.orientation = ORIENTATION_270
