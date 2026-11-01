#!/bin/sh
# Rebuilds KoboRoot.tgz from root/. Run on Linux/WSL: files must be owned by root with sane modes.
set -e
cd "$(dirname "$0")"
T=$(mktemp -d)
cp -r root/. "$T"
find "$T" -type d -exec chmod 755 {} +
find "$T" -type f -exec chmod 644 {} +
chmod 755 "$T/usr/local/koreader-autoboot/autoboot.sh"
tar --owner=0 --group=0 --numeric-owner -czf KoboRoot.tgz -C "$T" ./etc ./usr
rm -rf "$T"
tar -tvzf KoboRoot.tgz
