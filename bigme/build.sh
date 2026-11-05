#!/bin/sh
# Builds what EdiKOla puts on a Bigme B6 Pro Color (Android 14), as a folder:
#   KOReader.apk         the official KOReader for Android, arm64 (install it on the Bigme)
#   koreader/plugins/    EdiKOla (konewspaper.koplugin)
#   koreader/patches/    2-edikola-bigme.lua: color screen on Bigme
# Copy the koreader/ folder to the root of the Bigme's internal storage (it merges with KOReader's own).
# Run in Linux/WSL or Git Bash:  sh bigme/build.sh <out dir>.  The download is pinned by SHA-256 and cached.
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: build.sh <out dir>}
CACHE=${CACHE:-$HOME/.cache/edikola-build}
mkdir -p "$CACHE"

APK_URL=https://github.com/koreader/koreader/releases/download/v2026.07.1/koreader-android-arm64-v2026.07.1.apk
APK_SHA=89cecbe06eacd2ff7d91e37152d6beeb52809f2ca38060b6515ed8b00d152412
APK="$CACHE/$(basename "$APK_URL")"
[ -f "$APK" ] || curl -sfL -o "$APK" "$APK_URL"
echo "$APK_SHA  $APK" | sha256sum -c --quiet || { rm -f "$APK"; echo "checksum mismatch: $APK_URL" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/koreader/plugins" "$OUT/koreader/patches"
cp "$APK" "$OUT/KOReader.apk"
cp -r "$REPO/konewspaper.koplugin" "$OUT/koreader/plugins/"
cp "$REPO"/bigme/patches/*.lua "$OUT/koreader/patches/"
echo "built $OUT:"
find "$OUT" -maxdepth 3 | sort
