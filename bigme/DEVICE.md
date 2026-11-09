# Bigme B6 Pro Color: what the device is

Read from the device on 2026-11-08 (Termux `getprop`, then `adb` over wireless debugging). Nothing changed.

| | |
|---|---|
| Reports itself as | `Bigme/HiBreak_EEA/Smartphone`, model `HiBreak` |
| SoC | MediaTek MT6877 (Dimensity 900/1080), 8 cores, 7.6 GB RAM, 256 GB |
| Firmware | `Bigme_V1.020260803`, Android 14 (SDK 34), security patch 2025-08-05 |
| Kernel | 4.19.191 |
| Partitions | A/B (`ab_update=true`, on slot `_a`), dynamic partitions (`super`), Treble, VNDK 31 |
| Boot | bootloader locked (`flash.locked=1`, `vbmeta.device_state=locked`, `verifiedbootstate=green`) |
| OEM unlock | toggle off (`sys.oem_unlock_allowed=0`); `ro.oem_unlock_supported` not set |
| Storage | file-based encryption (FBE, metadata encryption) |
| Bigme services | `handwrittenservice` (`com.xrz.IHandwrittenService`), `xrz_display_policy_service` (`IDisplayPolicyManager`: per-app refresh modes, used by EdiKOla), `xrz_app_freeze_service`, `xrz_split_screen_service`, `xrz_system_proxy_service` (all `xrz.framework.manager.*`, in Bigme's framework) |

## What this means

- This is a **B6 Pro**, but its firmware reports `HiBreak` and the SoC is the same MT6877: it is built
  on the platform of the **Bigme HiBreak Pro** (e-ink phone), which has an active XDA community: its
  root and backup work should apply here. **To check** on this device before relying on it.
- **Unlock**: on the HiBreak Pro, Developer options -> OEM unlocking, then `adb reboot bootloader` and
  `fastboot flashing unlock`. Unlocking wipes all data (FBE).
- **Backup**: done on 2026-11-08, see [BACKUP.md](BACKUP.md) and change set 4 in [CHANGES.md](CHANGES.md).
  Neither BROM mode nor any key combination was needed: this unit reports `Target config 0x0`, with SBC,
  SLA and DAA all disabled, so [mtkclient](https://github.com/bkerler/mtkclient) reads it in plain
  preloader mode and the Kamakiri "Error on sending payload" failure seen on some MT6877 units never
  arises. Storage is UFS, so the preloader lives outside the GPT and is not in the backup.
- **Boot layout: this firmware has no `init_boot`.** `boot_a` is a legacy monolithic Android boot image,
  header version 2, holding both the kernel (13.74 MiB) and the ramdisk (11.02 MiB), not the post-GKI
  split. `init_boot_a`/`_b` and `vendor_boot_a`/`_b` exist as GPT entries, as MediaTek's scatter defines
  them, but they are blank and `vbmeta_a` does not describe them: its descriptors cover `boot`, `dtbo`,
  `product`, `vbmeta_system` and `vbmeta_vendor` only. So anything that patches the ramdisk, Magisk
  included, targets **`boot`**, not `init_boot`, despite this being Android 14.
  Checked 2026-11-09, after Magisk refused `init_boot_a` with "unable to unpack boot image".
- **OTA with root** works on the HiBreak Pro: re-root after each update; each OTA switches slot.
- **Debloat**: on the HiBreak Pro, apps removed with `pm uninstall --user 0` came back after a firmware
  update; `pm disable-user` holds. So `debloat.sh` only disables.
- **GSI**: one boots on the HiBreak Pro with HW overlays disabled. Whether the pen, E-Ink Center refresh
  modes and color survive is unknown: level 4 question.
- `com.mediatek.miravision.ui` (MiraVision) is MediaTek's display color tuning: a first candidate for
  feature 5 (color profiles), without root.

## Display: what Bigme already has (survey of 2026-11-08, no root)

- Home is **`com.android.launcher3`** (Bigme's xLauncher3, `/system/app/xLauncher3`), not
  `com.xrz.ebook.launcher`.
- E-ink tuning lives in system properties, read by Bigme's HWC and `xrz_display_policy_service`
  (policy version 9; per-app list: `dumpsys xrz_display_policy_service --policies`):
  - global: `vendor.xrz.global_color_enhance` (0), `global_contrast` (30), `global_brightness_level` (20),
    `global_color_mode` (0), `global_text_enhance`, `gpu_dither`, `gray_256_dither`,
    `force_global_refresh_mode` (-1 = per app), `auto_clean_enabled` (1), `clean_frequency`;
  - per content type, already defined: `sys.comic_color_enhance` 60 / `sys.comic_refresh_mode` 180,
    `sys.maga_color_enhance` 50 / `sys.maga_refresh_mode`, `sys.video_color_enhance` 30 /
    `sys.video_refresh_mode` 179; factory defaults `ro.vendor.xrz.default_*` (color enhance 30,
    refresh mode 178);
  - `persist.vendor.xrz.fps` 120, `fps_high` 50, `fps_low` 40.
- **These globals move on their own**: the values above are a snapshot, not settings that stay put.
  `global_color_mode` follows the foreground app's policy (read 0 with `com.android.launcher3` in front,
  2 with `com.xrz.standby`, whose policy says `appColorMode=2`). `global_contrast` was read as both 20
  and 30 in one session, and `global_color_enhance` was found at 60 some minutes after being set back to
  0, with no one touching it; neither matches the foreground policy's `appContrast=20` /
  `appColorEnhance=30`, so something besides the per-app policy writes them too (60 is also
  `sys.comic_color_enhance`). Checked 2026-11-08: `adb shell setprop vendor.xrz.global_color_enhance 60`
  **is** accepted and reads back at once, but it does not hold. For feature 5, drive the per-app policies
  through E-Ink Center instead of these properties.
- **Per-app profiles already exist**: the service holds 284 policies (Bigme's presets plus apps seen),
  each with `appDpi`, `refreshMode` (178 reading, 179 video/fast; `sys.comic_refresh_mode` 180),
  `refreshFrequency` (auto clean), `appContrast`, `appColorEnhance`, `appColorMode` (0 default,
  3 on video apps), `appBleachMode`/`appBleachTextPlus`/`appBleachIconColor`, `appAntiFlicker`,
  `appAntiAlias`, `appTextEnhance`, `appDarkLevel`. They are what E-Ink Center edits per app, so
  features 5 (color profiles) and 6 (video) start from E-Ink Center, no code. Presets worth copying:
  `com.xrz.video` (refresh 179, color mode 3, contrast 10, anti-flicker on).
  KOReader today: dpi 350, refresh 178, contrast 30, color enhance 30, color mode 0, bleach on (as for
  283 of 284 apps), anti-flicker off.
- Settings (`settings list system`): `app_bleach_filter=org.koreader.launcher,1,0,0,0`: Bigme's
  per-app "bleach" (whiter background) is on for KOReader.
- Pen: `handwrittenservice` v1.4.0, committer at ~75 FPS; `ro.vendor.xrz.pen_type` 3.
- `service call SurfaceFlinger 1022` (global saturation) is refused to adb shell: "Operation not permitted".

Sources: XDA threads
[HiBreak Pro (MT6877)](https://xdaforums.com/t/bigme-hibreak-pro-dimensity-900-mt6877-e-ink-phone.4723924/),
[HiBreak Pro Color root/debloat](https://xdaforums.com/t/bigme-hibreak-pro-color-color-s-root-magisk-debloat-general-impressions.4764527/),
[HiBreak Pro development](https://xdaforums.com/t/bigme-hibreak-pro-development-thread.4731041/);
[vbh.ai unlock guide](https://vbh.ai/unlocking-the-bootloader-and-rooting-the-hibreak-pro/).
