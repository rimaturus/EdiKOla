# Level 1: full backup of the Bigme's firmware (Linux PC)

Reads every partition of the GPT except `userdata` with [mtkclient](https://github.com/bkerler/mtkclient),
without unlocking or writing anything. It is what makes levels 3-4 reversible: `nvram`, `nvdata`,
`proinfo` and `protect*` hold this unit's IMEI and calibration, and Bigme publishes no firmware to
download. Done on this unit on 2026-11-08, see change set 4 in [CHANGES.md](CHANGES.md).
About 15 minutes, 14 GB free on the PC.

This unit needs **no exploit**. It reports `Target config 0x0`, so SBC, SLA and DAA are all disabled and
mtkclient talks to it in plain preloader mode. The `Error on sending payload` failure reported on some
MT6877 units does not arise here.

## 1. Install mtkclient (Ubuntu/Debian; other distros: its README-INSTALL.md)

```sh
sudo apt install git python3-venv libusb-1.0-0 libfuse2 adb
git clone --depth 1 https://github.com/bkerler/mtkclient ~/mtkclient
cd ~/mtkclient && python3 -m venv .venv && . .venv/bin/activate
pip install wheel setuptools pyusb pycryptodome pycryptodomex colorama pyserial \
    keystone-engine capstone unicorn mfusepy
sudo cp Setup/Linux/*.rules /etc/udev/rules.d/ && sudo udevadm control -R && sudo udevadm trigger
sudo usermod -aG dialout,plugdev $USER   # then log out and back in
```

Install the packages listed above, **not** `requirements.txt`: that one also pulls in PySide6 and
shiboken6 for the GUI, hundreds of MB the command line never loads. The PySide6 import in
`mtkclient/config/mtk_config.py` is wrapped in try/except with a stub class, so the CLI runs without it.
`flake8` is only for linting.

**Check**: `python mtk.py --help` prints the commands (V2.1.4 here).

## 2. Connect in preloader mode and read the partition table

1. Bigme switched **off**, USB cable plugged into the PC only, **not** into the Bigme.
2. `python mtk.py printgpt > gpt.txt`: it waits for the device.
3. Plug the cable into the Bigme, **no keys held**. It shows up as `0e8d:2000 MT65xx Preloader` and
   mtkclient prints `Detected regular mode !`.

The cable has to be plugged in *while mtkclient is already waiting*: the preloader accepts a handshake
only in the moment it gets powered. With the cable already attached and the device off, it instead
enumerates as `0e8d:20ff`, a single HID interface (charging), which mtkclient cannot talk to, and loops
on `Handshake failed, retrying...`. Unplug from the Bigme and plug back in to get out of that.

No key combination is needed on this unit, and BROM mode is never entered. After a session that ends
cleanly the next command connects on its own, with no new replug. Several reads can also be chained into
a single session, each carrying its own options:

```sh
python mtk.py multi "r vbmeta_a /tmp/v.bin;r boot_a /tmp/b.bin"
```

**Check**: a list of partitions (`boot_a`, `boot_b`, `vbmeta_a`, `super`, `nvram`, ... `userdata`).
On this unit the GPT holds 61 entries while `/dev/block/by-name` shows 74. The 13 extra are the three
UFS LUN nodes (`sda`, `sdb`, `sdc`), `bootloader1`, `bootloader2` and the six `preloader_*` aliases,
all of which live outside the GPT.

If it stops at `Error on sending payload`, **stop here** and send the full output, then run again with
`--debugmode` (log in `log.txt`). Nothing has been written.

## 3. Dump

```sh
python mtk.py rl ~/bigme-backup --skip userdata
cd ~/bigme-backup && sha256sum * > SHA256SUMS
```

Then switch the Bigme on normally (hold Power ~10 s if it stays dark).

It took 7 min 47 s at about 35 MB/s here, ending on `All Dumped partitions success`: 60 partitions plus
`gpt.bin` and `gpt_backup.bin`, 13.25 GiB. mtkclient also drops `.state` and `hwparam.json` into the
working directory; `.state` caches the session, so delete it if a later connect behaves oddly.

The logs in `~/bigme-backup` carry this unit's `ME_ID`, `SOC_ID` and UFS serial. Keep them on the PC;
they are not for the repo.

**Check**:
- one file per entry of `gpt.txt` except `userdata`, plus `gpt.bin` and `gpt_backup.bin`;
- read one again and compare: `python mtk.py r vbmeta_a /tmp/v.bin && cmp /tmp/v.bin ~/bigme-backup/vbmeta_a.bin`;
- copy `~/bigme-backup` to a second disk: these files are unique to this unit.

## The preloader is not in this backup

It lives on the UFS boot LUNs (`LU1` and `LU2`, 4 MB each), outside the GPT, so `rl` never reaches it.
Reading a LUN directly fails on this unit:

```
python mtk.py rf preloader_lu1.bin --parttype=lu1
Error on sending dev ctrl 0x40007: Exceed available range (0xc004000b)
```

The `--parttype=boot1` form is the eMMC convention and does not apply here: this unit is UFS
(Samsung KM8B8001JM-BC0, blocksize 0x1000, LU0 255.4 GB, LU1 and LU2 4 MB each).

mtkclient's own `dumppreloader` would get it, but it calls `mtk.crasher()` to drop the device into BROM
and then runs the Kamakiri payload, so it is **not** part of this read-only procedure. The two code paths
that pull the preloader out of RAM both require BROM mode *and* a preceding `bypass_security()`, which an
unprotected unit like this one never calls, so they stay out of reach in preloader mode.

This matters little in practice. Nothing in levels 2-3 writes the preloader, and because the unit is
unprotected, BROM mode stays available to write a known-good preloader back if it ever came to that.
To close the gap anyway: either root the device (level 3) and `dd` from `/dev/block/sda`, or run
`dumppreloader` as a deliberate, separately approved step.

## Restore (only when needed, after asking)

- One partition: `python mtk.py w boot_a ~/bigme-backup/boot_a.bin` (files are `<partition>.bin`).
- Writing to the flash is a brick risk: never without checking together which partitions and why.
  (`wl` writes a whole folder back; not for this one as is, since the folder also holds `gpt.bin`,
  `gpt_backup.bin`, the checksums and the logs.)
