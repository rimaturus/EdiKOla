#!/bin/sh
# Builds EdiKOla.apk for an Android phone: the official KOReader for Android (arm64) with EdiKOla
# (konewspaper.koplugin) already inside, so installing the APK is all there is to do.
# The plugin goes into the APK's own copy of KOReader (assets/module/koreader.7z), then the APK is re-signed
# with your key. Same app id as KOReader (org.koreader.launcher): uninstall an official KOReader first.
# Ascolta (news read aloud, offline): sherpa-onnx's C library goes next to KOReader's own (lib/arm64-v8a), the
# Piper voices Paola (Italian) and Alba (British English) into the plugin's voci/ (also left in $CACHE/voci).
# Needs: curl, 7z, zip, java.  Run:  sh android/build.sh <out dir>
# The key is made on the first run and must be kept: updates only install over an APK signed with the same key.
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: build.sh <out dir>}
CACHE=${CACHE:-$HOME/.cache/edikola-build}
KEYSTORE=${KEYSTORE:-$HOME/.config/edikola/android.jks}
KS_PASS=${KS_PASS:-edikola}
mkdir -p "$CACHE"

fetch() { # url sha256
    f="$CACHE/$(basename "$1")"
    [ -f "$f" ] || curl -sfL -o "$f" "$1"
    echo "$2  $f" | sha256sum -c --quiet || { rm -f "$f"; echo "checksum mismatch: $1" >&2; exit 1; }
}
APK_URL=https://github.com/koreader/koreader/releases/download/v2026.07.1/koreader-android-arm64-v2026.07.1.apk
fetch "$APK_URL" 89cecbe06eacd2ff7d91e37152d6beeb52809f2ca38060b6515ed8b00d152412
SIGNER_URL=https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar
fetch "$SIGNER_URL" e1299fd6fcf4da527dd53735b56127e8ea922a321128123b9c32d619bba1d835
SHERPA_URL=https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.6/sherpa-onnx-v1.13.6-android.tar.bz2
fetch "$SHERPA_URL" bb7f891b259f4faee5c55d4cc10d79a3ba2b27416e9320d2c4d044400834d75b
VOICES=https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models
fetch $VOICES/vits-piper-it_IT-paola-medium-int8.tar.bz2 2b975ed305391c056944a4dde67ee754dd824099503a860295bb4c1d724662d8
fetch $VOICES/vits-piper-en_GB-alba-medium-int8.tar.bz2 f7581d123ae977f64f3032bb247d4deeac8440e881d918d36fdd36d8f1030fb7

# voci/: it/ and en/ (model, tokens, model card), espeak-ng-data with the Italian and English dictionaries only
VOCI="$CACHE/voci"
if [ ! -d "$VOCI" ]; then
    rm -rf "$VOCI.tmp" && mkdir -p "$VOCI.tmp"
    for v in it:it_IT-paola en:en_GB-alba; do
        d="$VOCI.tmp/${v%%:*}" && mkdir -p "$d"
        tar xjf "$CACHE/vits-piper-${v#*:}-medium-int8.tar.bz2" -C "$d" --strip-components=1
    done
    mv "$VOCI.tmp/it/espeak-ng-data" "$VOCI.tmp/"
    rm -rf "$VOCI.tmp/en/espeak-ng-data"
    find "$VOCI.tmp/espeak-ng-data" -maxdepth 1 -name '*_dict' ! -name it_dict ! -name en_dict -delete
    mv "$VOCI.tmp" "$VOCI"
fi

if [ ! -f "$KEYSTORE" ]; then
    mkdir -p "$(dirname "$KEYSTORE")"
    keytool -genkeypair -keystore "$KEYSTORE" -storepass "$KS_PASS" -keypass "$KS_PASS" -alias edikola \
        -keyalg RSA -keysize 4096 -validity 36500 -dname "CN=EdiKOla" 2>/dev/null
    echo "new signing key: $KEYSTORE (keep it)"
fi

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cp "$CACHE/$(basename "$APK_URL")" "$W/app.apk"

# KOReader with EdiKOla. The version names the EdiKOla commit, so the app re-extracts it after an update.
REV="v2026.07.1-0-g$(git -C "$REPO" rev-parse --short=7 HEAD)"
mkdir -p "$W/assets/module" "$W/ko"
unzip -q -p "$W/app.apk" assets/module/koreader.7z > "$W/k.7z"
7z x -bd -y -o"$W/ko" "$W/k.7z" >/dev/null
cp -r "$REPO/konewspaper.koplugin" "$W/ko/plugins/"
cp -r "$VOCI" "$W/ko/plugins/konewspaper.koplugin/voci"
echo "$REV" > "$W/ko/git-rev"
printf '%s' "$REV" > "$W/assets/module/version.txt"
(cd "$W/ko" && 7z a -bd -mx=9 -m0=lzma2 "$W/assets/module/koreader.7z" . >/dev/null)

mkdir -p "$W/lib/arm64-v8a"
tar xjf "$CACHE/$(basename "$SHERPA_URL")" -C "$W/lib/arm64-v8a" --strip-components=3 \
    ./jniLibs/arm64-v8a/libsherpa-onnx-c-api.so ./jniLibs/arm64-v8a/libonnxruntime.so

zip -q -d "$W/app.apk" 'META-INF/*'
(cd "$W" && zip -q -0 app.apk assets/module/koreader.7z assets/module/version.txt \
    && zip -q app.apk lib/arm64-v8a/libsherpa-onnx-c-api.so lib/arm64-v8a/libonnxruntime.so)
java -jar "$CACHE/$(basename "$SIGNER_URL")" -a "$W/app.apk" -o "$W/signed" \
    --ks "$KEYSTORE" --ksAlias edikola --ksPass "$KS_PASS" --ksKeyPass "$KS_PASS" >/dev/null

mkdir -p "$OUT"
cp "$W"/signed/*.apk "$OUT/EdiKOla.apk"
echo "built $OUT/EdiKOla.apk ($REV)"
