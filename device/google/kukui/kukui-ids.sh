#!/system/bin/sh
# Chromebooks keep the serial number in the read-only VPD, which coreboot
# hands over in its table (coreboot_table, vpd-sysfs from vendor_dlkm).
# Depthcharge puts no androidboot.serialno on the command line, so
# ro.serialno stayed unset and Settings showed "unknown". An unset ro.*
# property can still be set once.
VPD=/sys/firmware/vpd/ro
i=0
while [ ! -r "$VPD/serial_number" ] && [ "$i" -lt 10 ]; do
    sleep 1
    i=$((i + 1))
done
if [ -z "$(getprop ro.serialno)" ] && [ -r "$VPD/serial_number" ]; then
    serial=$(tr -cd 'A-Za-z0-9-' < "$VPD/serial_number")
    [ -n "$serial" ] && setprop ro.serialno "$serial"
fi

# Settings shows "Hardware version" from ro.boot.hardware.revision.
# Coreboot puts the board revision and the SKU into the DT as 32-bit
# big-endian cells.
cell() {
    set -- $(od -An -tu1 "$1" 2>/dev/null)
    [ $# -eq 4 ] && echo $(( ($1 << 24) | ($2 << 16) | ($3 << 8) | $4 ))
}
CB=/proc/device-tree/firmware/coreboot
if [ -z "$(getprop ro.boot.hardware.revision)" ]; then
    rev=$(cell "$CB/board-id")
    sku=$(cell "$CB/sku-id")
    [ -n "$rev" ] && setprop ro.boot.hardware.revision "rev$rev${sku:+ sku$sku}"
fi
exit 0
