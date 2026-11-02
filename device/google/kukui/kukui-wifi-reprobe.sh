#!/system/bin/sh
# ath10k downloads its firmware over SDIO while the first eMMC boot is
# still writing userdata. That transfer times out, probe returns, and
# wlan0 is never registered. Later boots with a quiet disk succeed on
# the first try, so this only reloads the driver when the interface is
# missing. A second start of the same service must not bounce a live
# interface.
if [ -d /sys/class/net/wlan0 ]; then
    exit 0
fi
if [ -e /dev/.kukui-wifi-reprobe ]; then
    exit 0
fi
touch /dev/.kukui-wifi-reprobe

log() {
    echo "kukui-wifi: $*" > /dev/kmsg
}

log "wlan0 missing, waiting for the eMMC to go quiet"
quiet=0
n=0
while [ "$n" -lt 90 ]; do
    if [ -d /sys/class/net/wlan0 ]; then
        log "wlan0 appeared"
        exit 0
    fi
    before=$(awk '$3=="mmcblk0"{print $6+$10}' /proc/diskstats)
    sleep 1
    after=$(awk '$3=="mmcblk0"{print $6+$10}' /proc/diskstats)
    n=$((n + 1))
    if [ "$before" = "$after" ]; then
        quiet=$((quiet + 1))
        if [ "$quiet" -ge 4 ]; then
            break
        fi
    else
        quiet=0
    fi
done

log "reloading ath10k"
err=$(rmmod ath10k_sdio 2>&1) || log "rmmod ath10k_sdio: $err"
err=$(rmmod ath10k_core 2>&1) || log "rmmod ath10k_core: $err"
err=$(insmod /vendor/lib/modules/ath10k_core.ko 2>&1) || log "insmod ath10k_core: $err"
err=$(insmod /vendor/lib/modules/ath10k_sdio.ko 2>&1) || log "insmod ath10k_sdio: $err"

n=0
while [ "$n" -lt 40 ]; do
    if [ -d /sys/class/net/wlan0 ]; then
        log "wlan0 up"
        exit 0
    fi
    n=$((n + 1))
    sleep 1
done
log "wlan0 still missing"
exit 0
