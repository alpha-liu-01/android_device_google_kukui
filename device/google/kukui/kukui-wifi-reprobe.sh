#!/system/bin/sh
# The first boot after a fresh userdata writes that disk for a long time.
# ath10k pushes its firmware over SDIO during that window, the transfer
# times out, and the driver does not try again, so wlan0 never appears.
# The next boot is quiet and the same probe succeeds.
#
# Waiting on mmcblk0 misses a USB boot disk, and a single reload while the
# disk is still busy fails the same way. This waits out the first probe,
# then reloads until wlan0 exists. A boot that already has wlan0 is left
# alone. kukui-keep starts this from the ramdisk; the vendor service is
# the same script once a super image contains it.

log() {
    echo "kukui-wifi: $*" > /dev/kmsg
}

if ! mkdir /dev/.kukui-wifi-reprobe 2>/dev/null; then
    exit 0
fi

i=0
while [ "$i" -lt 180 ]; do
    if [ -f /vendor/lib/modules/ath10k_sdio.ko ] && [ -d /sys/class/net ]; then
        break
    fi
    i=$((i + 1))
    sleep 1
done

# A quiet boot registers wlan0 well inside this. Leave that interface up.
i=0
while [ "$i" -lt 150 ]; do
    if [ -d /sys/class/net/wlan0 ]; then
        log "wlan0 already present"
        exit 0
    fi
    if [ "$(getprop sys.boot_completed)" = "1" ] && [ "$i" -ge 20 ]; then
        break
    fi
    i=$((i + 1))
    sleep 1
done

if [ -d /sys/class/net/wlan0 ]; then
    log "wlan0 already present"
    exit 0
fi

log "wlan0 missing after the first probe"

data_disk() {
    dev=$(awk '$2=="/data"{print $1; exit}' /proc/mounts)
    name=${dev##*/}
    if [ -z "$name" ] || [ ! -e "/sys/class/block/$name" ]; then
        return
    fi
    parent=$(readlink -f "/sys/class/block/$name")
    parent=${parent%/*}
    echo "${parent##*/}"
}

sectors() {
    awk -v d="$1" '$3==d { print $6 + $10; exit }' /proc/diskstats
}

reload() {
    log "reloading ath10k"
    if [ -e /sys/bus/sdio/drivers/ath10k_sdio/mmc1:0001:1 ]; then
        echo mmc1:0001:1 > /sys/bus/sdio/drivers/ath10k_sdio/unbind 2>/dev/null || true
    fi
    err=$(rmmod ath10k_sdio 2>&1) || log "rmmod ath10k_sdio: $err"
    err=$(rmmod ath10k_core 2>&1) || log "rmmod ath10k_core: $err"
    sleep 1
    err=$(insmod /vendor/lib/modules/ath10k_core.ko 2>&1) || log "insmod ath10k_core: $err"
    err=$(insmod /vendor/lib/modules/ath10k_sdio.ko 2>&1) || log "insmod ath10k_sdio: $err"
}

reloaded=0
attempt=0
while [ "$attempt" -lt 12 ]; do
    if [ -d /sys/class/net/wlan0 ]; then
        break
    fi
    disk=$(data_disk)
    quiet=0
    spin=0
    while [ "$spin" -lt 40 ]; do
        if [ -d /sys/class/net/wlan0 ]; then
            break
        fi
        before=$(sectors "$disk")
        sleep 1
        after=$(sectors "$disk")
        spin=$((spin + 1))
        if [ -n "$disk" ] && [ -n "$before" ] && [ "$before" = "$after" ]; then
            quiet=$((quiet + 1))
            if [ "$quiet" -ge 5 ]; then
                break
            fi
        else
            quiet=0
        fi
    done
    if [ -d /sys/class/net/wlan0 ]; then
        break
    fi
    reload
    reloaded=1
    n=0
    while [ "$n" -lt 25 ]; do
        if [ -d /sys/class/net/wlan0 ]; then
            log "wlan0 up"
            break
        fi
        n=$((n + 1))
        sleep 1
    done
    attempt=$((attempt + 1))
done

if [ ! -d /sys/class/net/wlan0 ]; then
    log "wlan0 still missing"
    exit 0
fi

if [ "$reloaded" != 1 ]; then
    exit 0
fi

i=0
while [ "$i" -lt 30 ]; do
    on=$(settings get global wifi_on 2>/dev/null || true)
    if [ "$on" = "0" ]; then
        log "wifi_on is 0"
        exit 0
    fi
    if cmd wifi set-wifi-enabled enabled >/dev/null 2>&1; then
        log "framework wifi enabled"
        exit 0
    fi
    i=$((i + 1))
    sleep 1
done
log "wlan0 up, framework not ready"
exit 0
