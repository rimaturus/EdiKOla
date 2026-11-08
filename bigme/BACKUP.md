# Level 1: full backup of the Bigme's firmware (Linux PC)

Reads every partition except `userdata` with [mtkclient](https://github.com/bkerler/mtkclient), without
unlocking or writing anything. It is what makes levels 3–4 reversible: `nvram`, `nvdata`, `proinfo` and
`protect*` hold this unit's IMEI and calibration, and Bigme publishes no firmware to download.
Not yet tried on this device. About 1 hour, ~20 GB free on the PC.

## 1. Install mtkclient (Ubuntu/Debian; other distros: its README-INSTALL.md)

```sh
sudo apt install git python3-venv libusb-1.0-0 libfuse2 adb
git clone --depth 1 https://github.com/bkerler/mtkclient ~/mtkclient
cd ~/mtkclient && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt
sudo cp Setup/Linux/*.rules /etc/udev/rules.d/ && sudo udevadm control -R && sudo udevadm trigger
sudo usermod -aG dialout,plugdev $USER   # then log out and back in
```

**Check**: `python mtk.py --help` prints the commands.

## 2. Connect in BROM/preloader mode and read the partition table

1. Bigme switched **off**, USB cable plugged into the PC only.
2. `python mtk.py printgpt`: it waits for the device.
3. Plug the cable into the Bigme. If nothing happens: unplug, hold **Vol+ and Vol−** (or Vol+ + Power) and
   plug again; release when the tool reacts. From a running Bigme, `adb reboot edl` also works on the
   HiBreak Pro.

**Check**: a list of partitions (`boot_a`, `boot_b`, `vbmeta_a`, `super`, `nvram`, … `userdata`).
Save it: `python mtk.py printgpt > gpt.txt`.

If it stops at `Error on sending payload` (Kamakiri payload, reported on some MT6877 units), **stop here**
and send me the full output, run again with `--debugmode` (log in `log.txt`). Nothing has been written.

## 3. Dump

```sh
python mtk.py rl ~/bigme-backup --skip userdata
python mtk.py r preloader ~/bigme-backup/preloader_boot1.bin --parttype=boot1
cd ~/bigme-backup && sha256sum * > SHA256SUMS
```

Then switch the Bigme on normally (hold Power ~10 s if it stays dark).

**Check**:
- one file per partition of `gpt.txt` except `userdata`;
- read one again and compare: `python mtk.py r vbmeta_a /tmp/v.bin && cmp /tmp/v.bin ~/bigme-backup/vbmeta_a.bin`;
- copy `~/bigme-backup` to a second disk: these files are unique to this unit.

## Restore (only when needed, after asking)

- One partition: `python mtk.py w boot_a ~/bigme-backup/boot_a.bin` (files are `<partition>.bin`).
- Writing to the flash is a brick risk: never without checking together which partitions and why.
  (`wl` writes a whole folder back; not for this one as is, since it also holds `gpt.bin` and the preloader.)
