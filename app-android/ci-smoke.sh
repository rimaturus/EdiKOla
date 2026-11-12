#!/bin/bash
# Smoke test on an emulator (CI): installs the APK, goes through the main screens like a person would, and
# leaves screenshots, the UI tree and the log in $OUT. Run where `adb` sees one device: sh ci-smoke.sh <apk> <out>
APK=$1
OUT=${2:-smoke}
mkdir -p "$OUT"
PKG=it.rimaturus.edikola
n=0

shot() { n=$((n + 1)); adb exec-out screencap -p > "$OUT/$(printf %02d $n)-$1.png"; }

# tap the first element whose text or description is $1 (from the accessibility tree, as UI Automator sees it)
tap() {
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1
    xy=$(python3 - "$1" <<'PY'
import re, sys
xml = open("/tmp/ui.xml", encoding="utf-8").read()
want = sys.argv[1]
for m in re.finditer(r'<node [^>]*>', xml):
    n = m.group(0)
    t = re.search(r' text="([^"]*)"', n).group(1)
    d = re.search(r' content-desc="([^"]*)"', n).group(1)
    if want in (t, d):
        x1, y1, x2, y2 = map(int, re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n).groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
PY
)
    if [ -z "$xy" ]; then echo "NOT FOUND: $1" | tee -a "$OUT/steps.txt"; return 1; fi
    echo "tap $1 at $xy" >> "$OUT/steps.txt"
    adb shell input tap $xy
}

wait_for() { # text, seconds
    for i in $(seq 1 "$2"); do
        adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
        adb shell cat /sdcard/ui.xml 2>/dev/null | grep -q "$1" && return 0
        sleep 1
    done
    echo "TIMEOUT waiting for: $1" | tee -a "$OUT/steps.txt"
    return 1
}

adb shell cmd uimode night no
read W H <<EOF2
$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)
EOF2
echo "screen $W x $H" >> "$OUT/steps.txt"
adb install -r "$APK" 2>&1 | tee "$OUT/install.txt"
adb logcat -c
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 8
shot edicola-vuota

tap "Aggiorna" && sleep 5 && shot aggiornamento
wait_for "Ascolta" 240
sleep 20 # the rest of the papers
shot edicola

tap "Ascolta" && sleep 25 && shot player
adb shell dumpsys media_session > "$OUT/media_session.txt" 2>&1
sleep 60 && shot player-dopo
tap "Articolo successivo" && sleep 45 && shot player-articolo-2
adb shell dumpsys media_session > "$OUT/media_session-2.txt" 2>&1
adb shell input keyevent KEYCODE_VOLUME_DOWN; sleep 1; shot volume
adb shell dumpsys audio | grep -A3 -i "STREAM_MUSIC" > "$OUT/audio.txt" 2>&1
adb shell input keyevent KEYCODE_BACK; sleep 2

tap "Il Fatto Quotidiano" || tap "RaiNews"
sleep 3 && shot giornale
adb shell input tap $((W / 2)) $((H * 30 / 100)); sleep 3; shot articolo
adb shell input swipe $((W / 2)) $((H * 70 / 100)) $((W / 2)) $((H * 30 / 100)) 300; sleep 2; shot articolo-giu
adb shell input keyevent KEYCODE_BACK; sleep 1
adb shell input keyevent KEYCODE_BACK; sleep 1

tap "Sommario" && sleep 3 && shot sommario
tap "Giochi" && sleep 2 && shot giochi
tap "Cruciverba del giorno" && sleep 15 && shot cruciverba
adb shell input keyevent KEYCODE_BACK; sleep 1
tap "Sudoku medio" && sleep 10 && shot sudoku
adb shell input keyevent KEYCODE_BACK; sleep 1
tap "Libri" && sleep 2 && shot libri

adb shell cmd uimode night yes
sleep 3
tap "Edicola"; sleep 3; shot notte-edicola
tap "Giochi" && sleep 2 && shot notte-giochi

adb logcat -d > "$OUT/logcat.txt"
grep -E "FATAL|AndroidRuntime|$PKG|sherpa|EdiKOla" "$OUT/logcat.txt" | head -200 > "$OUT/logcat-app.txt"
echo "done" >> "$OUT/steps.txt"
