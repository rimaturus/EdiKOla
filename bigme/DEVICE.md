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
- **Unlock**: on the HiBreak Pro, Developer options → OEM unlocking, then `adb reboot bootloader` and
  `fastboot flashing unlock`. Unlocking wipes all data (FBE).
- **Backup**: the HiBreak Pro owners use [mtkclient](https://github.com/bkerler/mtkclient) in BROM mode
  (phone off, both volume keys held while plugging USB), dumping every partition except `userdata`.
  On some recent units the public Kamakiri payload fails on MT6877 ("Error on sending payload"). If that
  happens here, the fallback is to capture Bigme's own OTA package before unlocking.
- **OTA with root** works on the HiBreak Pro: re-root after each update; each OTA switches slot.
- **Debloat**: on the HiBreak Pro, apps removed with `pm uninstall --user 0` came back after a firmware
  update; `pm disable-user` holds. So `debloat.sh` only disables.
- **GSI**: one boots on the HiBreak Pro with HW overlays disabled. Whether the pen, E-Ink Center refresh
  modes and color survive is unknown: level 4 question.
- `com.mediatek.miravision.ui` (MiraVision) is MediaTek's display color tuning: a first candidate for
  feature 5 (color profiles), without root.

Sources: XDA threads
[HiBreak Pro (MT6877)](https://xdaforums.com/t/bigme-hibreak-pro-dimensity-900-mt6877-e-ink-phone.4723924/),
[HiBreak Pro Color root/debloat](https://xdaforums.com/t/bigme-hibreak-pro-color-color-s-root-magisk-debloat-general-impressions.4764527/),
[HiBreak Pro development](https://xdaforums.com/t/bigme-hibreak-pro-development-thread.4731041/);
[vbh.ai unlock guide](https://vbh.ai/unlocking-the-bootloader-and-rooting-the-hibreak-pro/).
