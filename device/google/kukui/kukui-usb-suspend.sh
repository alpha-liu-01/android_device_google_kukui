#!/system/bin/sh
# Apply the saved "power USB off during sleep" choice. The kernel default
# is 0, which leaves the USB host powered so a USB boot disk survives sleep.
NODE=/sys/devices/platform/soc/11201000.usb/suspend_power_off
CHOICE=/data/system/kukui_usb_suspend_power_off
if [ ! -e "$NODE" ]; then
    exit 0
fi
chmod 666 "$NODE"
if [ -f "$CHOICE" ]; then
    val=$(tr -d ' \n\r' < "$CHOICE")
else
    val=0
fi
case "$val" in
1) echo 1 > "$NODE" ;;
*) echo 0 > "$NODE" ;;
esac
