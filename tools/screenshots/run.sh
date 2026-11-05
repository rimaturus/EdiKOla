#!/bin/sh
# README screenshots from KOReader's desktop build, at the Kobo Nia's 758x1024 / 212 dpi.
# Needs: KOReader linux-x86_64 tarball extracted in $KO (bin/ lib/), SDL2, python3.
#   KO=~/kosim sh tools/screenshots/run.sh
# Bigme B6 Pro Color (1072x1448, 300 dpi, color, pen notes, its patch) into docs/images/bigme:
#   BIGME=1 KO=~/ko2607 sh tools/screenshots/run.sh    (HWR=1: also one real transcription, online)
set -e
REPO=$(cd "$(dirname "$0")/../.." && pwd)
if [ -n "$BIGME" ]; then W=1072 H=1448 DPI=300 COLOR=true NOTES=true LANG_KO=it_IT IMAGES=docs/images/bigme
else W=758 H=1024 DPI=212 COLOR=false NOTES=false LANG_KO=en IMAGES=docs/images; fi
WORK=${WORK:-$HOME/.cache/edikola-shots${BIGME:+-bigme}}
rm -rf "$WORK" && mkdir -p "$WORK/home" "$WORK/cfg/koreader/patches" "$WORK/shots"

python3 "$REPO/tools/screenshots/make_demo.py" "$WORK/home"
rm -rf "$KO/lib/koreader/plugins/konewspaper.koplugin"
cp -r "$REPO/konewspaper.koplugin" "$KO/lib/koreader/plugins/"
cp "$REPO/tools/screenshots/2-edikola-shots.lua" "$WORK/cfg/koreader/patches/"
[ -n "$BIGME" ] && cp "$REPO"/bigme/patches/*.lua "$WORK/cfg/koreader/patches/" # does nothing off Android: loads, at least
# color_rendering=false: grayscale like the Nia (and no emulator-only color notice)
printf 'return { ["start_with"] = "filemanager", ["home_dir"] = "%s", ["lastdir"] = "%s", ["quickstart_shown_version"] = 999999999, ["color_rendering"] = %s, ["konewspaper_notes"] = %s, ["language"] = "%s" }\n' \
    "$WORK/home" "$WORK/home" "$COLOR" "$NOTES" "$LANG_KO" > "$WORK/cfg/koreader/settings.reader.lua"

cd "$KO/lib/koreader"
KO_HOME="$WORK/cfg/koreader" XDG_DOCUMENTS_DIR="$WORK/home" KNP_SHOTS="$WORK/shots" KNP_HWR=$HWR \
EMULATE_READER_W=$W EMULATE_READER_H=$H EMULATE_READER_DPI=$DPI SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-offscreen} \
    ./reader.lua "$WORK/home" > "$WORK/log.txt" 2>&1 || true

mkdir -p "$REPO/$IMAGES"
cp "$WORK"/shots/*.png "$REPO/$IMAGES/"
grep -E "SHOT STEP FAILED|Error|error" "$WORK/log.txt" | head -20 || true
ls "$REPO/$IMAGES"
