#!/bin/sh
# Builds everything EdiKOla puts on a Kobo, as a folder to copy onto the Kobo drive:
#   .adds/koreader/   KOReader (official Kobo package, pruned by prune.sh) + EdiKOla + LocalSend + patches
#   .adds/nm/koreader NickelMenu entry to start KOReader, for when Nickel boots (fallback)
#   .kobo/KoboRoot.tgz  NickelMenu + the Nickel-free boot (autoboot/root), installed by the Kobo at its next start
# Run in Linux/WSL (tar must write root ownership):  sh minimal/build.sh <out dir>
# Downloads are pinned by SHA-256 and cached in $CACHE.
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: build.sh <out dir>}
CACHE=${CACHE:-$HOME/.cache/edikola-build}
mkdir -p "$CACHE"

fetch() { # url sha256 -> path in cache
    f="$CACHE/$(basename "$1")"
    [ -f "$f" ] || curl -sfL -o "$f" "$1"
    echo "$2  $f" | sha256sum -c --quiet >&2 || { rm -f "$f"; echo "checksum mismatch: $1" >&2; exit 1; }
    echo "$f"
}
KO=$(fetch https://github.com/koreader/koreader/releases/download/v2026.07.1/koreader-kobo-v2026.07.1.zip \
    0f36a62ce73b12516f969e4ad7862cc06920afb03c7bd4db29a0d990bdd84b2f)
NM=$(fetch https://github.com/pgaskin/NickelMenu/releases/download/v0.6.0/KoboRoot.tgz \
    322ff9aa863860e8f5f7e0b55cae561c54bf95983b9bce1d19819d1225d064af)
LS=$(fetch https://github.com/kaikozlov/localsend.koplugin/releases/download/v1.4.6/localsend-koplugin-armv7.zip \
    1034f1a81b2726e0df8ffaa31598ce1666bc01075ce28adcbc9e167fb3b838ce)

rm -rf "$OUT"
mkdir -p "$OUT/.adds/nm" "$OUT/.kobo"
unzip -q "$KO" "koreader/*" -d "$OUT/.adds"
sh "$REPO/minimal/prune.sh" "$OUT/.adds/koreader"
cp -r "$REPO/konewspaper.koplugin" "$OUT/.adds/koreader/plugins/"
unzip -q "$LS" -d "$OUT/.adds/koreader/plugins"
mkdir -p "$OUT/.adds/koreader/patches"
cp "$REPO"/minimal/*.lua "$OUT/.adds/koreader/patches/"

echo "menu_item : main : KOReader : cmd_spawn : quiet : exec /mnt/onboard/.adds/koreader/koreader.sh" > "$OUT/.adds/nm/koreader"

# One KoboRoot.tgz for both: the Kobo installs a single package per start
T=$(mktemp -d)
tar -xzf "$NM" -C "$T"
cp -r "$REPO/autoboot/root/." "$T/"
find "$T" -type f -exec chmod 644 {} +
chmod 755 "$T/usr/local/Kobo/imageformats/libnm.so" "$T/usr/local/koreader-autoboot/autoboot.sh"
# files only, like NickelMenu's own package: no entries for /, /etc or /mnt/onboard (FAT) to re-own or re-mode
(cd "$T" && find . -type f | sort | tar -czf "$OUT/.kobo/KoboRoot.tgz" --owner=0 --group=0 --numeric-owner -T -)
rm -rf "$T"

echo "built $OUT: $(du -sh "$OUT" | cut -f1)"
tar -tvzf "$OUT/.kobo/KoboRoot.tgz"
