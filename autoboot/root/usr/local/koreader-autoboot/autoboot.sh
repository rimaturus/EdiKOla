#!/bin/sh
# EdiKOla boot: KOReader instead of Nickel. udev runs this for loop0; when depends on rcS:
#
# - Usual boot: rcS restores /dev from /etc/udev.tgz and runs "udevadm trigger" only on its last line,
#   right after starting Nickel. This script then hands over to koreader.sh at once, which stops Nickel
#   (as when KOReader is started from NickelMenu) and starts it again when KOReader exits.
# - First boot after a reset or an update (no /etc/udev.tgz yet): the trigger comes early, before
#   /mnt/onboard is mounted. The script bind-mounts itself over /usr/local/Kobo/nickel for this boot,
#   so rcS's "nickel -platform kobo -skipFontLoad &" starts it instead and Nickel never loads.
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
FAIL=$ADDS/edikola-bootfail
log() { echo "$(cut -d' ' -f1 /proc/uptime) $*" >>"$TLOG"; }

# Fallbacks and bookkeeping before KOReader; false when Nickel should run instead
want_koreader() {
    n=$(cat "$FAIL" 2>/dev/null)
    n=${n:-0}
    if [ -e "$ADDS/noautoboot" ] || [ "$n" -ge 3 ]; then
        log "stock Nickel (noautoboot, or $n failed starts)"
        cat "$TLOG" >>"$ADDS/boot.log"
        return 1
    fi
    echo $((n + 1)) >"$FAIL"
    sync
    killall -q on-animator.sh # rcS's boot animation, which Nickel would stop
    log "KOReader starting"
    # ponytail: log grows ~100 bytes per boot; trim if it ever matters
    cat "$TLOG" >>"$ADDS/boot.log"
    (
        sleep 60
        pkill -0 -f reader.lua && rm -f "$FAIL" && sync
    ) &
}

case "$0" in
*/nickel)
    # Started by rcS as "nickel". Re-exec under our own name: koreader.sh checks "pkill -0 nickel"
    # to decide whether to kill Nickel, and would kill us.
    exec "$SELF" boot "$@" ;;
esac

case "$1" in
boot) # early hook: rcS has just started us in Nickel's place
    shift # "$@" is now Nickel's own arguments, for the fallback
    umount "$NICKEL" # the real Nickel is back: fallback, and koreader.sh's "restart Nickel"
    log "rcS done"
    want_koreader || exec "$NICKEL" "$@"
    killall -q hindenburg
    # Nickel reads this FIFO; without a reader, udev and udhcpc scripts block writing to it.
    rm -f /tmp/nickel-hardware-status
    # No Nickel (VIA_NICKEL=false): koreader.sh does Wi-Fi, USB and power-off itself, and reboots on exit.
    cd "$ADDS/koreader" && [ -x koreader.sh ] && exec ./koreader.sh
    log "koreader.sh missing, stock Nickel"
    exec "$NICKEL" "$@" ;;
takeover) # usual boot: Nickel has just been started
    log "Nickel started"
    want_koreader || exit 0
    cd "$ADDS/koreader" && [ -x koreader.sh ] && exec ./koreader.sh
    log "koreader.sh missing, stock Nickel"
    exit 0 ;;
esac

# udev. Once per boot: the rule can fire on both of rcS's triggers.
[ -e "$TLOG" ] && exit 0
if grep -q " /mnt/onboard " /proc/mounts; then
    log "udev: late trigger"
    # udev waits for (and may kill) what it runs: detach
    if command -v setsid >/dev/null; then
        setsid "$SELF" takeover </dev/null >/dev/null 2>&1 &
    else
        "$SELF" takeover </dev/null >/dev/null 2>&1 &
    fi
else
    log "udev: early trigger, Nickel hooked"
    mount -o bind "$SELF" "$NICKEL" || log "udev: bind failed, stock boot"
fi
exit 0
