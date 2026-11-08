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

**Revert**: `sh bigme/debloat.sh undo` re-enables them all; one package:
`adb shell pm enable <package>`. If the device doesn't boot: recovery (Power + Vol+) → factory reset,
which clears `/data` and with it every disabled state (and the user's data).
