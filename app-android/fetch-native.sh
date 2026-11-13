#!/bin/sh
# Puts what the app needs and git doesn't keep into the source tree (run from anywhere; CI runs it):
#   app/src/main/jniLibs/arm64-v8a/  sherpa-onnx v1.13.6 (speech engine) and onnxruntime
#   app/src/main/assets/voci/        Piper voices Paola (it), Alba (en_GB) and Riccardo (it2, the podcast's second
#                                    host), int8, and espeak-ng data
# Downloads are pinned by SHA-256 and cached in $CACHE.
set -e
APP=$(cd "$(dirname "$0")" && pwd)/app/src/main
CACHE=${CACHE:-$HOME/.cache/edikola-build}
mkdir -p "$CACHE"
fetch() { # url sha256
    f="$CACHE/$(basename "$1")"
    [ -f "$f" ] || curl -sfL -o "$f" "$1"
    echo "$2  $f" | sha256sum -c --quiet || { rm -f "$f"; echo "checksum mismatch: $1" >&2; exit 1; }
}
SHERPA=https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.6/sherpa-onnx-v1.13.6-android.tar.bz2
fetch $SHERPA bb7f891b259f4faee5c55d4cc10d79a3ba2b27416e9320d2c4d044400834d75b
VOICES=https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models
fetch $VOICES/vits-piper-it_IT-paola-medium-int8.tar.bz2 2b975ed305391c056944a4dde67ee754dd824099503a860295bb4c1d724662d8
fetch $VOICES/vits-piper-en_GB-alba-medium-int8.tar.bz2 f7581d123ae977f64f3032bb247d4deeac8440e881d918d36fdd36d8f1030fb7
fetch $VOICES/vits-piper-it_IT-riccardo-x_low-int8.tar.bz2 afc2ea457fd45420dbdd87db4b3927b4fc97b00511964d474bb43e03092d37c1

mkdir -p "$APP/jniLibs/arm64-v8a"
tar xjf "$CACHE/$(basename $SHERPA)" -C "$APP/jniLibs/arm64-v8a" --strip-components=3 \
    ./jniLibs/arm64-v8a/libsherpa-onnx-jni.so ./jniLibs/arm64-v8a/libonnxruntime.so

V="$APP/assets/voci"
rm -rf "$V" && mkdir -p "$V/it" "$V/en" "$V/it2"
tar xjf "$CACHE/vits-piper-it_IT-paola-medium-int8.tar.bz2" -C "$V/it" --strip-components=1
tar xjf "$CACHE/vits-piper-en_GB-alba-medium-int8.tar.bz2" -C "$V/en" --strip-components=1
tar xjf "$CACHE/vits-piper-it_IT-riccardo-x_low-int8.tar.bz2" -C "$V/it2" --strip-components=1
mv "$V/it/espeak-ng-data" "$V/"
rm -rf "$V/en/espeak-ng-data" "$V/it2/espeak-ng-data" "$V"/*/*.onnx.json
find "$V/espeak-ng-data" -maxdepth 1 -name '*_dict' ! -name it_dict ! -name en_dict -delete
echo "native libs and voices ready in $APP"
