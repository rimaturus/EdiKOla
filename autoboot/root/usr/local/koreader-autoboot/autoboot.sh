#!/bin/sh
# EdiKOla boot: KOReader starts in Nickel's place, so Nickel never loads.
#
# udev runs this early in rcS (udevadm trigger), before /mnt/onboard is mounted. It bind-mounts
# this script over /usr/local/Kobo/nickel for this boot only (nothing on the rootfs changes).
# rcS's last line, "nickel -platform kobo -skipFontLoad &", then starts this script instead.
#
#   Stock boot: create .adds/noautoboot on the Kobo drive (Nickel starts as usual).
#   Self-healing: after 3 KOReader starts in a row that didn't stay up 60 s, Nickel starts
#   instead, until .adds/edikola-bootfail is deleted.
#   Timings: .adds/boot.log (seconds since power-on).
#   Remove: delete /etc/udev/rules.d/99-koreader-autoboot.rules (or factory reset).

SELF=/usr/local/koreader-autoboot/autoboot.sh
NICKEL=/usr/local/Kobo/nickel
ADDS=/mnt/onboard/.adds
TLOG=/tmp/edikola-boot.log
log() { echo "$(cut -d' ' -f1 /proc/uptime) $*" >>"$TLOG"; }

case "$0" in
*/nickel)
    # Started by rcS as "nickel". Re-exec under our own name: koreader.sh checks "pkill -0 nickel"
    # to decide whether to kill Nickel, and would kill us.
    exec "$SELF" boot "$@" ;;
esac

if [ "$1" != boot ]; then
    # udev. The rule fires again on rcS's later "udevadm trigger": hook once per boot.
    [ -e "$TLOG" ] && exit 0
    log "udev: Nickel hooked"
    mount -o bind "$SELF" "$NICKEL" || log "udev: bind failed, stock boot"
    exit 0
fi

shift # "$@" is now Nickel's own arguments, for the fallback
umount "$NICKEL" # the real Nickel is back: fallback, and koreader.sh's "restart Nickel"
log "rcS done"

FAIL=$ADDS/edikola-bootfail
n=$(cat "$FAIL" 2>/dev/null)
n=${n:-0}
if [ -e "$ADDS/noautoboot" ] || [ "$n" -ge 3 ]; then
    log "stock Nickel (noautoboot, or $n failed starts)"
    cat "$TLOG" >>"$ADDS/boot.log"
    exec "$NICKEL" "$@"
fi
echo $((n + 1)) >"$FAIL"
sync

# Nickel would stop the boot animation; koreader.sh stops Nickel's helpers only when it finds Nickel.
killall -q on-animator.sh hindenburg
# Nickel reads this FIFO; without a reader, udev and udhcpc scripts block writing to it.
rm -f /tmp/nickel-hardware-status

log "KOReader starting"
# ponytail: log grows ~100 bytes per boot; trim if it ever matters
cat "$TLOG" >>"$ADDS/boot.log"
(
    sleep 60
    pkill -0 -f reader.lua && rm -f "$FAIL" && sync
) &
# koreader.sh sees no Nickel (VIA_NICKEL=false): it does Wi-Fi, USB and power-off itself,
# and reboots on exit. rcS already exported PLATFORM, PRODUCT, INTERFACE and WIFI_MODULE.
cd "$ADDS/koreader" && [ -x koreader.sh ] && exec ./koreader.sh
log "koreader.sh missing, stock Nickel"
exec "$NICKEL" "$@"
