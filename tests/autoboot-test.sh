#!/bin/sh
# Runs autoboot.sh through simulated boots: real bind mounts, busybox tools, fake Nickel/KOReader.
# Needs root and a private mount namespace, so nothing touches the host:
#   wsl -u root unshare -m sh tests/autoboot-test.sh      (or: sudo unshare -m sh tests/autoboot-test.sh)
set -e
SRC=$(cd "$(dirname "$0")/.." && pwd)/autoboot/root/usr/local/koreader-autoboot/autoboot.sh
W=$(mktemp -d /var/tmp/abtest.XXXXXX)
cp "$SRC" "$W/autoboot.sh"
mkdir "$W/bin"
for a in $(busybox --list); do [ "$a" = sleep ] || ln -s "$(command -v busybox)" "$W/bin/$a"; done
for t in pkill killall; do # not in every busybox build (the Kobo's has them)
    [ -e "$W/bin/$t" ] || ln -s "$(command -v $t)" "$W/bin/$t"
done
printf '#!/bin/sh\nexec busybox sleep 1\n' >"$W/bin/sleep" # the 60 s health check, sped up
chmod +x "$W/bin/sleep"
export PATH="$W/bin"

mount --make-rprivate /
for d in /tmp /mnt /usr/local; do mount -t tmpfs none $d; done
mkdir -p /usr/local/koreader-autoboot /usr/local/Kobo /mnt/onboard/.adds/koreader
cp "$W/autoboot.sh" /usr/local/koreader-autoboot/autoboot.sh
chmod 755 /usr/local/koreader-autoboot/autoboot.sh
printf '#!/bin/sh\necho "nickel $*" >/tmp/out\n' >/usr/local/Kobo/nickel
chmod 755 /usr/local/Kobo/nickel
KO=/mnt/onboard/.adds/koreader/koreader.sh
ADDS=/mnt/onboard/.adds

# $1 = healthy (KOReader stays up) or crash (exits at once)
fake_koreader() {
    cat >"$KO" <<EOF
#!/bin/sh
pkill -0 nickel && v=yes || v=no
echo "koreader via_nickel=\$v" >/tmp/out
[ "$1" = healthy ] && sh -c 'busybox sleep 3; :' reader.lua &
exit 0
EOF
    chmod 755 "$KO"
}

boot() { # what rcS does, in order
    rm -f /tmp/edikola-boot.log /tmp/out /tmp/nickel-hardware-status
    mkfifo /tmp/nickel-hardware-status
    /usr/local/koreader-autoboot/autoboot.sh # udevadm trigger
    /usr/local/koreader-autoboot/autoboot.sh # rcS's second trigger: must not hook again
    [ "$(grep -c ' /usr/local/Kobo/nickel ' /proc/mounts)" = 1 ] || fail "nickel not hooked exactly once"
    /usr/local/Kobo/nickel -platform kobo -skipFontLoad
    busybox sleep 2 # health check
    grep -q ' /usr/local/Kobo/nickel ' /proc/mounts && fail "nickel still hooked"
    cat /tmp/out
}
fail() { echo "FAIL: $*"; cat /tmp/edikola-boot.log; exit 1; }
expect() { [ "$1" = "$2" ] || fail "expected '$2', got '$1'"; }

fake_koreader healthy
expect "$(boot)" "koreader via_nickel=no"
[ -e $ADDS/edikola-bootfail ] && fail "healthy start left a failure count"
[ -e /tmp/nickel-hardware-status ] && fail "Nickel FIFO left behind"
grep -q "KOReader starting" $ADDS/boot.log || fail "boot.log missing"

fake_koreader crash
for i in 1 2 3; do expect "$(boot)" "koreader via_nickel=no"; done
expect "$(cat $ADDS/edikola-bootfail)" 3
expect "$(boot)" "nickel -platform kobo -skipFontLoad"

rm $ADDS/edikola-bootfail
fake_koreader healthy
touch $ADDS/noautoboot
expect "$(boot)" "nickel -platform kobo -skipFontLoad"
rm $ADDS/noautoboot

rm "$KO"
expect "$(boot)" "nickel -platform kobo -skipFontLoad"

rm -rf "$W"
echo "autoboot: all boots OK"
