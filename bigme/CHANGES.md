# System changes – Bigme B6 Pro Color (FW Bigme_V1.020260803)

Each change says what was found, what was done, and how to revert it. Device facts: [DEVICE.md](DEVICE.md).

## 2026-11-08 – Change set 1: ADB debloat (disable only)

**Found**: stock firmware, bootloader locked, no root, no full backup yet (needs a PC). Only
`com.google.android.gms.supervision` was disabled.

**What**
- Done before the backup by choice: `pm disable-user` only writes package state in `/data`, no partition
  is touched.
- `sh bigme/debloat.sh`, run from Termux on a phone through wireless debugging: disables the 55 packages
  in `debloat.txt` (Chinese education suite, Bigme store/cloud/AI/translators, Google extras, MediaTek
  test apps, DuraSpeed).
- Checked: 55 × `new state: disabled-user`; `pm list packages -d` = 56 before and after a reboot (Bigme's
  `xrz_app_freeze_service` doesn't re-enable them).

**Revert**: `sh bigme/debloat.sh undo` re-enables them all; one package:
`adb shell pm enable <package>`. If the device doesn't boot: recovery (Power + Vol+) → factory reset,
which clears `/data` and with it every disabled state (and the user's data).

## 2026-11-08 – Change set 2: KOReader + EdiKOla, installed through adb

**Found**: no KOReader on the device.

**What** (from Termux on a phone, wireless debugging; same files as [docs/BIGME.md](../docs/BIGME.md))
- `sh bigme/build.sh out`, then `adb install out/KOReader.apk` (official v2026.07.1 arm64,
  `org.koreader.launcher`) and `adb push out/koreader /sdcard/` (EdiKOla plugin + Bigme patch).
- `adb shell appops set --uid org.koreader.launcher MANAGE_EXTERNAL_STORAGE allow`: the "all files" access
  KOReader asks for on first start.
- `adb shell dumpsys deviceidle whitelist +org.koreader.launcher`: no battery optimization, so an
  Aggiorna isn't stopped with the screen off.

**Revert**: `adb shell dumpsys deviceidle whitelist -org.koreader.launcher`, then
`adb uninstall org.koreader.launcher`; `adb shell rm -r /sdcard/koreader` removes settings and plugin
(the `KoNewspaper`, `Libri`, `Appunti` folders stay).

## 2026-11-08 – Change set 3: minimal launcher and apps (Play Store)

**Found**: home screen is Bigme's xLauncher3 (`com.android.launcher3`); Play Store and GMS work.

**What**
- From the Play Store: **Olauncher** (`app.olauncher`, open source, text only) as home screen, **LocalSend**
  (`org.localsend.localsend_app`), **Kiwix** (`org.kiwix.kiwixmobile`), **AntennaPod**
  (`de.danoeh.antennapod`). **Termux** (`com.termux`) from F-Droid's APK, installed with `adb install`
  (the Play Store build lags behind).
- Olauncher set as default home from its own settings; its daily wallpaper off (e-ink).
- Per-app display profiles set in E-Ink Center (Bigme's own per-app policies, see DEVICE.md).

**Revert**: Settings → Apps → Default apps → Home app → the Bigme launcher; then uninstall what isn't
wanted (`adb uninstall <package>`). E-Ink Center profiles: reset per app in E-Ink Center.
