#!/bin/sh
# EdiKOla's KOReader: the official package minus what the newsstand never uses.
# Usage: sh minimal/prune.sh <koreader dir>   (the folder holding reader.lua)
# Plugins are loaded and fonts scanned at every start, so those two make startup faster.
# Hyphenation patterns stay: they load only for a book in that language, and a missing one could break it.
set -e
K=${1:?usage: prune.sh <koreader dir>}
[ -f "$K/reader.lua" ] || { echo "no reader.lua in $K" >&2; exit 1; }
cd "$K"

# Plugins: the newsstand, phone transfers, SSH for maintenance, sleep/power-off, taps and swipes
KEEP=" konewspaper localsend SSH autosuspend gestures "
for p in plugins/*.koplugin; do
    case "$KEEP" in *" $(basename "$p" .koplugin) "*) ;; *) rm -rf "$p" ;; esac
done

# Menus in Italian (English is built in)
for l in l10n/*/; do
    [ "$l" = "l10n/it_IT/" ] || rm -rf "$l"
done

# Fonts: Noto Sans/Serif for text and menus; nerdfonts and FreeFont stay for icons and rare symbols.
# Gone: the Chinese/Japanese/Korean font (16 MB) and the Arabic, Bengali and Devanagari ones.
rm -f fonts/noto/NotoSansCJK* fonts/noto/NotoNaskh* fonts/noto/NotoSansArabic* \
      fonts/noto/NotoSansBengali* fonts/noto/NotoSansDevanagari*

echo "pruned: $(du -sh . | cut -f1), plugins: $(ls plugins | tr '\n' ' ')"
