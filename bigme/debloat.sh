#!/bin/sh
# Applies bigme/debloat.txt on the Bigme, through adb (PC or Termux).
#   sh bigme/debloat.sh            disable them (pm disable-user)
#   sh bigme/debloat.sh uninstall  uninstall them for user 0 (system apps stay in /system;
#                                  non-system ones, Kindle and Multi_TTS, are deleted for good)
#   sh bigme/debloat.sh undo       bring them back (install-existing, then enable)
# With more than one adb device, set ANDROID_SERIAL first (e.g. ANDROID_SERIAL=192.168.1.50:41235).
set -e
sed 's/#.*//' "$(dirname "$0")/debloat.txt" | while read -r p; do
    [ -n "$p" ] || continue
    case "$1" in
        uninstall) echo "pm uninstall --user 0 $p" ;;
        undo) echo "cmd package install-existing --user 0 $p; pm enable $p" ;;
        *) echo "pm disable-user --user 0 $p" ;;
    esac
done | adb shell sh
