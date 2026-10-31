#!/system/bin/sh
# SurfaceFlinger and drm_hwcomposer abort in logd, not in kmsg.
# kukui-keep is already writing kmsg to pmOS_boot and fsyncing it.
# A second mount of that partition returns EBUSY, so this mirror is
# the path that still exists after a forced power-off.
# The same stream is also rotated on /data for a boot that stays up.
# Keep the filter narrow. An unfiltered logcat fills the printk ring
# and the lines we need are the ones that get overwritten.

marker() {
    printf 'KUKUI_LOG %s\n' "$1" > /dev/kmsg 2>/dev/null || true
}

i=0
while [ "$i" -lt 30 ]; do
    if [ -S /dev/socket/logdr ]; then
        break
    fi
    i=$((i + 1))
    sleep 1
done

marker "kukui-logcat started"

set -- \
    SurfaceFlinger:V drmhwc:V HwcComposer:V HWComposer:V \
    RenderEngine:V libEGL:E libGLESv2:E minigbm:V gralloc4:V \
    AllocatorService:E BufferQueueProducer:E \
    BootAnimation:I libc:F DEBUG:I AndroidRuntime:E tombstoned:E \
    EventHub:I InputReader:W \
    netd:E Netd:E '*:S'

logcat -b crash -b system -b main -v threadtime \
    -f /data/kukui-logcat.txt -r 4096 -n 3 "$@" &

# threadtime lines differ only in the timestamp when the same error repeats.
# Keep the first copy in kmsg. The /data file still has every line.
while true; do
    logcat -b crash -b system -b main -v threadtime "$@" |
        while IFS= read -r line; do
            key=$(printf '%s\n' "$line" | sed 's/^[0-9-]* [0-9:.]* *[0-9]* *[0-9]* //')
            if [ "$key" = "$prev" ]; then
                continue
            fi
            prev=$key
            printf 'KUKUI_LOG %.900s\n' "$line" > /dev/kmsg 2>/dev/null || true
        done
    marker "kukui-logcat restart"
    sleep 1
done
