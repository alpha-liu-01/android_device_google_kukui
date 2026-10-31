# Goodix 27C6:0E30 stylus node. The kernel names it
# "hid-over-i2c 27C6:0E30 Stylus", so this file is separate from the
# finger digitizer. It is already a direct touchscreen, and the axes
# have the same extra 90 degrees the finger node had before
# ORIENTATION_270.
device.internal = 1
touch.deviceType = touchScreen
touch.orientation = ORIENTATION_270
