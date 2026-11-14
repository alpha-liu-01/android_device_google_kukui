#!/system/bin/sh
# Apply the saved "power USB off during sleep" choice. The kernel default
# is 0, which leaves the USB host powered so a USB boot disk survives sleep.
# Without a saved choice, an eMMC boot uses 1, so mem_sleep becomes deep.
# A USB boot keeps 0: powering the port off would end the running system.
NODE=/sys/devices/platform/soc/11201000.usb/suspend_power_off
CHOICE=/data/system/kukui_usb_suspend_power_off
if [ ! -e "$NODE" ]; then
    exit 0
fi
chmod 666 "$NODE"
if [ -f "$CHOICE" ]; then
    val=$(tr -d ' \n\r' < "$CHOICE")
elif [ "$(getprop ro.boot.boot_devices)" = "soc/11230000.mmc" ]; then
    val=1
else
    val=0
fi
case "$val" in
1) echo 1 > "$NODE" ;;
*) echo 0 > "$NODE" ;;
esac
