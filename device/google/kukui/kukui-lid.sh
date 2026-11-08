#!/system/bin/sh
# Closing the keyboard cover is SW_LID on cros_ec_buttons. Android sleeps
# for that switch only when Settings.Global.lid_behavior is 1. The
# framework copies config_lidControlsSleep into the setting once, when
# settings are first created, so an update of an existing data partition
# still has 0. A later change is left alone.
STAMP=/data/system/kukui_lid_behavior
if [ -f "$STAMP" ]; then
    exit 0
fi
i=0
while [ "$i" -lt 30 ]; do
    if settings put global lid_behavior 1; then
        echo 1 > "$STAMP"
        chmod 644 "$STAMP"
        exit 0
    fi
    i=$((i + 1))
    sleep 1
done
exit 1
