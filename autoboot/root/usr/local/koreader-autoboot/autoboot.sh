#!/bin/sh
# Opens KOReader once Nickel is up. koreader.sh stops Nickel and restarts it on exit,
# so Nickel stays the fallback. Skip once: create /mnt/onboard/.adds/noautoboot
# Remove: delete /etc/udev/rules.d/99-koreader-autoboot.rules (or factory reset).

FLAG=/tmp/koreader-autoboot.done
[ -e "$FLAG" ] && exit 0

# udev waits on RUN scripts: detach and return immediately
if [ "$1" != "run" ]; then
    touch "$FLAG"
    if command -v setsid >/dev/null; then
        setsid "$0" run </dev/null >/dev/null 2>&1 &
    else
        "$0" run </dev/null >/dev/null 2>&1 &
    fi
    exit 0
fi

KO=/mnt/onboard/.adds/koreader/koreader.sh
i=0
until pkill -0 nickel && [ -x "$KO" ]; do
    i=$((i + 1))
    [ "$i" -gt 180 ] && exit 0
    sleep 1
done
# ponytail: fixed delay for Nickel to settle (DB, Wi-Fi state); raise if KOReader starts too early
sleep 5
[ -e /mnt/onboard/.adds/noautoboot ] && exit 0

cd /mnt/onboard/.adds/koreader && exec "$KO"
