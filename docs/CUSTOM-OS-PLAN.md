# Plan: a custom OS for a snappier EdiKOla

Goal: the Kobo Nia boots to the Edicola fast, and every tap feels immediate. The aim is to be quicker
than the stock Kobo was when new, without losing a way back.

Status: **plan only**. Nothing here is on the device yet.

## Where the time goes today (to measure first)

The boot chain today: U-Boot → Kobo kernel 4.1.15 → `/etc/init.d/rcS` → Nickel (the stock UI) → our
udev hook waits for Nickel, plus 5 s → `koreader.sh` stops Nickel → KOReader → Edicola.

Rough guess: about 60–75 s from power-on to Edicola, of which 30–40 s is Nickel starting up only to be
killed again. That guess needs measuring, so phase 0 comes first.

## Success criteria

| Metric | Today (est.) | Target |
|---|---|---|
| Cold boot → Edicola | ~60–75 s | **< 20 s** (phase 1), < 12 s (phase 3) |
| Wake from sleep → usable | ~1–2 s | < 1 s |
| Tap → screen reacts | to measure | < 150 ms |
| Page turn | to measure | < 300 ms |
| Way back to stock | factory reset | factory reset, plus a full storage image |

## Phase 0: measure and back up (low risk)

1. **Timestamps**: `autoboot.sh` logs uptime at each step to `/mnt/onboard/.adds/boot.log`
   (onboard mounted, Nickel up, KOReader started). KOReader's `crash.log` already records when
   KOReader starts.
2. **Full backup**: with root over SSH (KOReader's SSH plugin), `dd` the internal storage
   (check on a teardown whether the Nia uses an internal microSD card) to the PC and keep the image.
   This is the safety net for every later phase. Also note the button combo for a factory reset.

## Phase 1: skip Nickel (biggest win, moderate risk)

- Ship a `KoboRoot.tgz` that patches `rcS` minimally: just before Nickel starts, if
  `/mnt/onboard/.adds/edikola-boot` exists, run `koreader.sh` instead. If KOReader exits or crashes
  3 times in a row, fall back to starting Nickel. This is the approach community launchers
  (KSM, kfmon-based boot scripts) have used for years. Reuse their rcS snippets; don't invent new ones.
- KOReader already handles running without Nickel (`VIA_NICKEL=false` in `koreader.sh`): Wi-Fi
  modules, USB storage mode and power-off are all done by KOReader itself.
- **Fallback**: delete the flag file over USB to get the stock boot back. Firmware updates overwrite
  `rcS`, which is another reason to block OTA updates (Kobo account sync off / hosts entry).
- Expected: Edicola in about 20 s.

## Phase 2: slim KOReader (low risk, all in settings)

- Turn off plugins EdiKOla doesn't use (through the `plugins_disabled` setting): coverbrowser, statistics,
  vocabbuilder, wallabag, opds, calibre, kosync, terminal, texteditor, perceptionexpander,
  newsdownloader, japanese, exporter, profiles, hotkeys, systemstat. Each one costs load time and RAM.
- Prune the bundled fonts to Noto Serif/Sans (fewer fonts to scan at startup), and keep the font
  cache warm.
- CPU: set the `interactive`/`ondemand` governor at a higher idle floor while the Edicola is showing,
  and `powersave` while asleep.
- E-ink: use the A2/"fast" waveform for UI updates (menus, page arrows), and GC16 (full refresh)
  only for photos and every 6 pages. Look at KOReader's `refresh_*` settings and the mxcfb refresh
  modes in `ffi/framebuffer_mxcfb`.
- Build editions ahead of time: when the Kobo is charging and on Wi-Fi, download that morning's
  papers, so tapping a tile never waits on the network.

## Phase 3: a minimal rootfs (high effort, high reward)

- Buildroot image for armv7 (Cortex-A7, i.MX6ULL). It keeps Kobo's **vendor kernel 4.1.15 and its
  modules** (e-ink driver, Wi-Fi, touch), with busybox init and only what KOReader needs (glibc,
  wpa_supplicant, udhcpc, dropbear).
- Init goes straight to KOReader: no Nickel, no Qt, no Kobo databases, no D-Bus.
- Expected: about 10 s to Edicola, and less RAM pressure, which also means faster page turns.
- Prerequisites: a serial console (UART pads on the board), the phase 0 image, and time. This is
  weeks of evenings, not a weekend.

## Phase 4: research (optional)

- A mainline kernel for the i.MX6ULL: check postmarketOS/upstream for a Kobo Nia device tree and the
  state of the EPDC (e-ink controller) driver. Without a working EPDC driver there is no screen, so
  this stays research until someone shows it booting.

## Risks and rules

- Never write to the rootfs without the phase 0 image on the PC.
- Each phase lands on `dev` first. It goes to `master` only after a week of daily use with no crash.
- Every phase keeps a documented one-step way back (flag file, factory reset, or `dd` restore),
  logged in `CHANGES.md`.
