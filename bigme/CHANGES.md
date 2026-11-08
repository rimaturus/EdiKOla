# System changes - Bigme B6 Pro Color (FW Bigme_V1.020260803)

Each change says what was found, what was done, and how to revert it. Device facts: [DEVICE.md](DEVICE.md).

## 2026-11-08 - Change set 1: ADB debloat (disable only)

**Found**: stock firmware, bootloader locked, no root, no full backup yet (needs a PC). Only
`com.google.android.gms.supervision` was disabled.

**What**
- Done before the backup by choice: `pm disable-user` only writes package state in `/data`, no partition
  is touched.
- `sh bigme/debloat.sh`, run from Termux on a phone through wireless debugging: disables the 55 packages
  in `debloat.txt` (Chinese education suite, Bigme store/cloud/AI/translators, Google extras, MediaTek
  test apps, DuraSpeed).
- Checked: 55 x `new state: disabled-user`; `pm list packages -d` = 56 before and after a reboot (Bigme's
  `xrz_app_freeze_service` doesn't re-enable them).

**Revert**: `sh bigme/debloat.sh undo` re-enables them all; one package:
`adb shell pm enable <package>`. If the device doesn't boot: recovery (Power + Vol+) -> factory reset,
which clears `/data` and with it every disabled state (and the user's data).

## 2026-11-08 - Change set 2: KOReader + EdiKOla, installed through adb

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

## 2026-11-08 - Change set 3: extra apps (Play Store), Bigme launcher kept

**Found**: home screen is Bigme's xLauncher3 (`com.android.launcher3`); Play Store and GMS work.

**What**
- From the Play Store: **Olauncher** (`app.olauncher`, open source, text only), **LocalSend**
  (`org.localsend.localsend_app`), **Kiwix** (`org.kiwix.kiwixmobile`), **AntennaPod**
  (`de.danoeh.antennapod`). **Termux** (`com.termux`) from F-Droid's APK, installed with `adb install`
  (the Play Store build lags behind).
- **The home screen stays on Bigme's xLauncher3.** Olauncher is installed and does declare a HOME
  activity, so it can be selected, but it was never made the default and it stays that way by choice.
- Per-app display profiles set in E-Ink Center (Bigme's own per-app policies, see DEVICE.md).

**Corrected on 2026-11-08**: this entry used to say Olauncher had been set as the default home from its
own settings. It never was. `adb shell cmd role get-role-holders android.app.role.HOME` answers
`com.android.launcher3`, and the Bigme launcher is what the device starts on.

**Checked** (during the change set 4 session): `pm list packages -3` lists the five apps above,
Olauncher 6.9.1, LocalSend 1.18.2, Kiwix 3.14.1, AntennaPod 3.12.3, Termux googleplay.2026.10.09,
next to KOReader 2026.07.1 from change set 2. Two more that no change set installed are present too,
`com.amazon.kindle` and `org.Multi_TTS`.

**Revert**: uninstall what isn't wanted (`adb uninstall <package>`). The home screen needs no revert,
it was never changed. E-Ink Center profiles: reset per app in E-Ink Center.

## 2026-11-08 - Change set 4: firmware backup (read-only)

**Found**: no backup existed yet. The unit reports `Target config 0x0`, so SBC, SLA and DAA are all
disabled: mtkclient connects in plain preloader mode (`0e8d:2000`, `Detected regular mode !`) and needs
no Kamakiri exploit, the failure reported on some other MT6877 units. Storage is UFS, not eMMC
(blocksize 0x1000, LU0 255.4 GB, LU1 and LU2 4 MB each), so the preloader sits on the boot LUNs outside
the GPT. The GPT holds 61 entries against the 74 names in `/dev/block/by-name`: the 13 extra are `sda`,
`sdb`, `sdc`, `bootloader1`, `bootloader2` and the six `preloader_*` aliases.

**What** (Linux PC over USB, device off; full procedure in [BACKUP.md](BACKUP.md))
- mtkclient V2.1.4 in `~/mtkclient`, venv with the command-line dependencies only: `requirements.txt`
  also pulls PySide6 and shiboken6 for the GUI, hundreds of MB the CLI never loads.
- `python mtk.py printgpt > gpt.txt`, then `python mtk.py rl ~/bigme-backup --skip userdata`:
  7 min 47 s at about 35 MB/s, ending on `All Dumped partitions success`.
- Backup in `~/bigme-backup`, **outside the repo**: 62 images and 13.25 GiB, the 60 GPT partitions except
  `userdata` plus `gpt.bin` and `gpt_backup.bin`. Neither the images nor `gpt.txt` are committed.
- `sha256sum * > SHA256SUMS` over the folder, 69 lines, 70 files and 13.27 GiB in total.
- The logs there carry this unit's `ME_ID`, `SOC_ID` and UFS serial, so they stay on the PC.

**Checked**
- Every GPT entry has its file except `userdata`, skipped on purpose; the only two files not in the GPT
  are `gpt.bin` and `gpt_backup.bin`.
- `vbmeta_a` read again in a later session and compared with `cmp`: identical, same SHA256.
- Second copy made on an external 32 GB drive, whole-device ext4 labelled `BIGME-BACKUP`, under
  `bigme-backup/` next to a `README.txt` that names the unit and repeats the restore caveats. Checked by
  reading it back off the drive with `sha256sum -c SHA256SUMS`: 69 of 69 files OK. The drive sits at
  49 per cent used.
- These images cannot be regenerated: they are unique to this unit, `nvram`, `nvdata`, `proinfo` and
  `protect1`/`protect2` carry its IMEI and calibration, and Bigme publishes no firmware to download.

**Gap**: the preloader is not in the backup. `rf --parttype=lu1` fails with `Exceed available range`, and
the only route left, `dumppreloader`, crashes the preloader into BROM to run the Kamakiri payload, so it
was left out of a read-only backup. Low impact: nothing in levels 2-3 writes the preloader, and BROM mode
stays reachable on this unprotected unit. Details and how to close it: [BACKUP.md](BACKUP.md).

**Revert**: nothing to revert, every command was a read. Do not delete `~/bigme-backup`: Bigme publishes
no firmware, so these images are the only copy of this unit's calibration partitions.
