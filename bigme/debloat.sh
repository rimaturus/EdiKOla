#!/bin/sh
# Disables the packages listed in bigme/debloat.txt on the Bigme, through adb (PC or Termux).
#   sh bigme/debloat.sh        disable them
#   sh bigme/debloat.sh undo   enable them again
# With more than one adb device, set ANDROID_SERIAL first (e.g. ANDROID_SERIAL=192.168.1.50:41235).
set -e
cmd="disable-user --user 0"
[ "$1" = undo ] && cmd=enable
sed 's/#.*//' "$(dirname "$0")/debloat.txt" | while read -r p; do
    [ -n "$p" ] && echo "pm $cmd $p"
done | adb shell sh
