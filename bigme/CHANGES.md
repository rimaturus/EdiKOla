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
next to KOReader 2026.07.1 from change set 2. Two more are present that no change set installed,
`com.amazon.kindle` and `org.Multi_TTS`; they survived the wipe of change set 5, so they are part
of the stock image.

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

**26 of the 62 images are all-zero, and that is correct.** Twenty are `_b`-slot partitions, blank on a
unit that has never taken an OTA. The others are `boot_para`, `otp`, `para`, `sec1` (MediaTek parameter
and one-time-programmable areas) and `init_boot_a` / `vendor_boot_a`, which this firmware does not use at
all: `boot_a` is a monolithic header-v2 image carrying the ramdisk itself, and `vbmeta_a` describes no
`init_boot` or `vendor_boot`. See [DEVICE.md](DEVICE.md). Confirmed 2026-11-09 by parsing the images:
`boot_a` has the `ANDROID!` magic with a 13.74 MiB kernel and an 11.02 MiB ramdisk, `vbmeta_a` the `AVB0`
magic, `super` the logical-partition geometry magic at offset 4096.

**What the checks above did and did not cover**: they established that every GPT entry has a file, that
the files are self-consistent against `SHA256SUMS`, and that one partition (`vbmeta_a`) re-read identically
from the device. They did **not** look at whether each image held plausible content. That gap surfaced on
2026-11-09 when Magisk could not unpack `init_boot_a`; checking the headers then confirmed the dump is
faithful, but the content check belongs in the procedure, not in hindsight.

**Gap**: the preloader is not in the backup. `rf --parttype=lu1` fails with `Exceed available range`, and
the only route left, `dumppreloader`, crashes the preloader into BROM to run the Kamakiri payload, so it
was left out of a read-only backup. Low impact: nothing in levels 2-3 writes the preloader, and BROM mode
stays reachable on this unprotected unit. Details and how to close it: [BACKUP.md](BACKUP.md).

**Revert**: nothing to revert, every command was a read. Do not delete `~/bigme-backup`: Bigme publishes
no firmware, so these images are the only copy of this unit's calibration partitions.

## 2026-11-08 - Change set 5: bootloader unlocked (level 3, destructive)

**Found**: `sys.oem_unlock_allowed` read 0 and `ro.oem_unlock_supported` was unset, so it was an open
question whether Bigme shipped the OEM unlocking toggle at all. It is there, and enabling it in
Developer options moved the property to 1. The bootloader then reported `unlock_ability = 16777216`
(0x01000000, the value 1 with its bytes swapped, the way several MediaTek bootloaders report it),
`unlocked: no`, `secure: yes`, `product: k6877v1_64_k419`, slot `a`.

**Prepared first**, because unlocking wipes `/data` and `/sdcard` lives in `/data/media`, which the
firmware backup skipped on purpose:
- `/sdcard` pulled to `~/bigme-userdata-20261108/sdcard`: 857 MiB in 1405 files, with all 25 top-level
  folders matching the device's own per-folder file counts. `Appunti` was empty, so no pen notes existed.
- The configuration that is not in `/sdcard` captured to `~/bigme-userdata-20261108/config`: the E-Ink
  Center per-app policies (`dumpsys xrz_display_policy_service --policies`), the `system`, `secure` and
  `global` settings namespaces, the 56 disabled packages, the full `getprop`, the deviceidle whitelist.
- That and `~/bigme-backup` both copied to the external ext4 drive labelled `BIGME-BACKUP` and checked by
  reading them back off it: 69 of 69 firmware files and 1413 of 1413 user-data files OK.

**What**
- Developer options -> OEM unlocking, enabled by hand on the device.
- `adb reboot bootloader`, then `fastboot flashing unlock`, using the current official platform-tools
  (fastboot 37.0.1, unpacked in `~/platform-tools`). Ubuntu's packaged fastboot is 28.0.2 from 2018 and
  was deliberately not used. The bootloader answered `Start unlock flow` and finished in 3.5 s with no
  on-screen key confirmation, which some MediaTek bootloaders skip. `fastboot getvar unlocked` now
  answers `yes`.
- `fastboot reboot`. The first boot after the wipe reformats `/data` and is slow.

**Cost, as expected**: everything in `/data` is gone, so change sets 1 to 3 have to be redone. The 56
disabled packages come back with `sh bigme/debloat.sh`; KOReader and EdiKOla with `sh bigme/build.sh out`
and the adb steps of change set 2; the Play Store and F-Droid apps by reinstalling them. The E-Ink Center
per-app profiles have to be re-entered by hand, since without root there is no documented way to write
them back. adb access is gone until Developer options and USB debugging are on again and the PC is
re-authorised.

**Checked after the first boot**: `ro.boot.verifiedbootstate` is `orange` (was `green`),
`ro.boot.flash.locked` is 0 (was 1), `sys.oem_unlock_allowed` 1, slot still `_a`, firmware still
`1763796060`, `sys.boot_completed` 1. The wipe is confirmed too: third-party packages down from 8 to 2,
disabled packages from 56 to 1 (the stock state change set 1 started from), and `/sdcard` back to the
stock empty skeleton, 0 files, with `Appunti`, `KoNewspaper`, `Note`, `koreader`, `ScreenShot`,
`XRZBookCache` and `XRZNoteCache` gone. The device boots and runs normally; it shows the orange-state
warning at startup, as an unlocked bootloader does.

**Revert**: `fastboot flashing lock` re-locks the bootloader and wipes `/data` a second time. Only do it
with stock, unmodified `boot`, `init_boot` and `vbmeta` in place: locking a device whose boot chain has
been modified is a reliable way to make it refuse to boot. Those images are in the backup.
Nothing has been flashed and there is no root yet: the only thing this change set altered is the lock
state.

## 2026-11-09 - Change set 6: root with Magisk 31.1 (level 3)

**Found**: Magisk refused `init_boot_a` with "unable to unpack boot image", because that image is 8 MiB
of zeros. This firmware has no `init_boot`: `boot_a` is a monolithic header-v2 Android boot image holding
the ramdisk itself. Details in [DEVICE.md](DEVICE.md). So the patch target is `boot`, not `init_boot`,
Android 14 notwithstanding.

**What**
- Magisk 31.1 from the project's own GitHub release, sha256
  `89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7`, 10679283 bytes. The release-asset
  host answered 504 through this network on four attempts, so it was fetched from the GitHub API asset
  endpoint instead, same source. `adb install`, which reports version 31.1.
- `boot_a.bin` from the verified backup copied to `boot_a.img` (sha256 identical to the backup entry) and
  pushed to `/sdcard/Download`, then patched in the app with Install -> Select and Patch a File.
- `fastboot flash boot magisk_patched-31100_QyCVw.img`, which the bootloader resolved to `boot_a`:
  40960 KB written in about a second. `vbmeta` was deliberately left stock, and that was enough. Neither
  `--disable-verity` nor `--disable-verification` was needed, which fits Magisk patching with
  `KEEPVERITY=true` and `KEEPFORCEENCRYPT=true`.

**Validated before flashing**, since a bad boot image is the brick risk here: `ANDROID!` magic and header
version 2 preserved, page size 2048, kernel size byte-for-byte unchanged at 14411775, ramdisk grown from
11552975 to 11734976 bytes, and the first differing byte at offset 16, which is the ramdisk-size field.
Magisk's own log says `Stock boot image detected`, adds `init` plus `overlay.d/sbin/magisk.xz` and
`init-ld.xz`, and backs the stock `init` up to `.backup/init` inside the ramdisk.

**Checked after reboot**: boot completes, `magisk -V` 31100, `magisk -v` `31.1:MAGISK:R`,
`magisk --path` `/debug_ramdisk`, and `/debug_ramdisk/su` present. `verifiedbootstate` orange,
`flash.locked` 0, slot still `_a`, firmware still `1763796060`. `su` from `adb shell` answers
`Permission denied` until Superuser access is set to include ADB in the Magisk app; that is a Magisk
setting, not a flashing problem.

**Revert**: `fastboot flash boot ~/bigme-backup/boot_a.bin` puts the stock image back, or Magisk's own
Uninstall -> Restore Images does it from the device. The stock `init` also lives inside the patched
ramdisk at `.backup/init`. Re-locking the bootloader must come only after the stock `boot` is restored:
locking with a patched boot chain is a reliable way to make the device refuse to start.
