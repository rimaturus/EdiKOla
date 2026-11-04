#!/bin/sh
# README screenshots from KOReader's desktop build, at the Kobo Nia's 758x1024 / 212 dpi.
# Needs: KOReader linux-x86_64 tarball extracted in $KO (bin/ lib/), SDL2, python3.
#   KO=~/kosim sh tools/screenshots/run.sh
set -e
REPO=$(cd "$(dirname "$0")/../.." && pwd)
WORK=${WORK:-$HOME/.cache/edikola-shots}
rm -rf "$WORK" && mkdir -p "$WORK/home" "$WORK/cfg/koreader/patches" "$WORK/shots"

python3 "$REPO/tools/screenshots/make_demo.py" "$WORK/home"
rm -rf "$KO/lib/koreader/plugins/konewspaper.koplugin"
cp -r "$REPO/konewspaper.koplugin" "$KO/lib/koreader/plugins/"
cp "$REPO/tools/screenshots/2-edikola-shots.lua" "$WORK/cfg/koreader/patches/"
cp "$REPO"/minimal/*.lua "$WORK/cfg/koreader/patches/" # same patches as the Kobo build
# color_rendering=false: grayscale like the Nia (and no emulator-only color notice)
printf 'return { ["start_with"] = "filemanager", ["home_dir"] = "%s", ["lastdir"] = "%s", ["quickstart_shown_version"] = 999999999, ["color_rendering"] = false }\n' \
    "$WORK/home" "$WORK/home" > "$WORK/cfg/koreader/settings.reader.lua"

cd "$KO/lib/koreader"
KO_HOME="$WORK/cfg/koreader" XDG_DOCUMENTS_DIR="$WORK/home" KNP_SHOTS="$WORK/shots" \
EMULATE_READER_W=758 EMULATE_READER_H=1024 EMULATE_READER_DPI=212 SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-offscreen} \
    ./reader.lua "$WORK/home" > "$WORK/log.txt" 2>&1 || true

mkdir -p "$REPO/docs/images"
cp "$WORK"/shots/*.png "$REPO/docs/images/"
grep -E "SHOT STEP FAILED|Error|error" "$WORK/log.txt" | head -20 || true
ls "$REPO/docs/images"
