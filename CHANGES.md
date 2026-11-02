# KOReader changes – Kobo Nia (N306, FW 4.38.23555)

## 2026-10-27 – Change set 0: install KOReader (one-time exception to rule 3, approved)

**What**
- Extracted official OCP-KOReader-v2026.03.zip (MobileRead t=314220, MD5 266551f49d4a62f2e65edafac1c8fd1d) to F:\.
  Writes: `.adds/koreader/`, `.adds/kfmon/`, `.adds/nm/`, `.kobo/KoboRoot.tgz`, `kfmon.png`, `koreader.png`.
- `.kobo/Kobo/Kobo eReader.conf`: appended `[FeatureSettings]` + `ExcludeSyncFolders` (line from KOReader wiki, Kobo installation page).

**Why**
- KOReader was not installed. ExcludeSyncFolders stops Nickel (FW 4.17+) from indexing hidden folders like `.adds/`.

**Revert**
- Config: copy `backup/2026-10-27_1937_preinstall/Kobo eReader.conf` back over `F:\.kobo\Kobo\Kobo eReader.conf`.
- KOReader: delete `.adds/koreader`, `.adds/kfmon`, `.adds/nm`, `kfmon.png`, `koreader.png`.
  KFMon/NickelMenu binaries live in rootfs after first boot; a firmware reinstall removes them. NickelMenu also uninstalls by creating `.adds/nm/uninstall`.

## 2026-10-27 – Change set 0b: reinstall after files went missing

**Found after first reboot (drive now D:\)**
- Nickel auto-installed firmware 4.38.23828 (was 4.38.23555); `.kobo/kobo-update-4.38.23828.zip` is still on disk.
- `.adds/koreader`, `.adds/kfmon`, `.adds/nm/{koreader,kfmon}` were gone; only NickelMenu's `doc` was left. Root PNGs remained.
- The `ExcludeSyncFolders` line was gone too. Nickel had rewritten the config, with a new `[FeatureSettings] AcceptPreviewUpgrades=true`.
- Cause not confirmed. Suspects: unflushed writes before unplug, Nickel rewriting its config, or the firmware update.

**What**
- Re-added `ExcludeSyncFolders` under the existing `[FeatureSettings]` (backup: `backup/2026-10-27_2000_reinstall/`).
- Re-extracted the same OCP zip (MD5 verified); 1039/1039 files on disk; flushed the volume cache (Write-VolumeCache).

**Revert**: same as change set 0, using the 2000_reinstall config backup.

## 2026-10-27 – Change set 0c: launch KOReader directly from NickelMenu

**Found**: `.kobo/KoboRoot.tgz` was still pending (not processed on the last eject), so KFMon is not installed on FW 4.38.23828. NickelMenu showed a config error, most likely from the KFMon generator.

**What**
- `.adds/nm/koreader`: uncommented the direct `cmd_spawn ... koreader.sh` menu item (KOReader wiki, NickelMenu method).
- `.adds/nm/kfmon`: commented out `generator : main : kfmon`.

**Why**: direct launch needs no KFMon and survives firmware updates.

**Revert**: copy both files back from `backup/2026-10-27_2008_nm/`.

## 2026-11-01 – Change set 1: reinstall on factory-reset device + ad-free news

**Found**: device was factory-reset (FW back to 4.28.18406, setup not finished at `LastFTEStep=BEGIN`); KOReader, NickelMenu, and config changes were all gone.

**What**
- Backed up the user partition (`.kobo`, `.kobo-images`, `.adobe-digital-editions`) to `backup/2026-11-01_factory/`.
- Re-extracted OCP-KOReader-v2026.03.zip (MD5 266551f49d4a62f2e65edafac1c8fd1d) and redid change sets 0b and 0c: `ExcludeSyncFolders`, direct NM launch, and the KFMon generator turned off.
- Added `.adds/koreader/news/feed_config.lua` for KOReader's built-in News Downloader: NPR, BBC World, and Guardian World, each as full article plus images, filtered to the article body only.

**Revert**: factory reset (it restores Nickel and 4.28 from the recovery partition), or delete `.adds/koreader`, `.adds/kfmon`, `.adds/nm`, `kfmon.png`, `koreader.png`, then copy the config back from `backup/2026-11-01_factory/.kobo/Kobo/`.

## 2026-11-01 – Change set 2: boot straight into KOReader + news as home

**Found**: setup finished; FW auto-updated to 4.38.23852; the OCP KoboRoot.tgz was processed; KOReader launches and exits cleanly (crash.log 14:21).

**What**
- `.kobo/KoboRoot.tgz` (source: `autoboot/`): adds udev rule `/etc/udev/rules.d/99-koreader-autoboot.rules` → `/usr/local/koreader-autoboot/autoboot.sh`. Once per boot it waits for Nickel, then runs `koreader.sh`, which stops Nickel and restarts it on exit. Nickel stays installed as the fallback.
- `settings.reader.lua`: `home_dir`/`lastdir` = news folder, `start_with = filemanager` (backup: `backup/2026-11-01_factory/settings.reader.lua`).

**Skip once**: create `.adds/noautoboot` on the drive. **Revert**: factory reset, or delete the rule over SSH. A firmware update also wipes it.

## 2026-11-01 – Change set 3: KoNewspaper (newsstand home screen)

**Found**: auto-start worked. The log shows KOReader started at 14:29:41, 15 s after Nickel, but at first glance it looked like it hadn't opened.

**What**
- `.adds/koreader/plugins/konewspaper.koplugin` (source: `konewspaper.koplugin/`):
  - Newsstand screen covers KOReader's file browser: 6 newspaper tiles plus "I miei libri" and "Aggiorna tutti".
  - Tapping a tile opens today's edition, downloading it first if needed. Each edition is one EPUB (front page with headlines, one chapter per article, up to 3 photos), kept for 3 days in `KoNewspaper/<id>/`.
  - Articles are extracted with a text-density method (`knp_extract.lua`): no menus, ads, sidebars or outbound links.
  - In the reader, a "◀ Edicola" button sits top-left.
  - Applied once: font size 26, top margin 50, Wi-Fi on/off without prompts, full refresh every 6 pages plus on photo pages.
  - Newspaper list: `giornali.lua`.
- `autoboot/`: delay cut from 15 s to 5 s, with a new `.kobo/KoboRoot.tgz`.

**Tests**: `texlua konewspaper-test.lua` (fixtures) and `texlua konewspaper-test.lua live` (all feeds). A full EPUB build was simulated on the PC for all 6 papers: valid XML, nothing missing from the manifest.

**Revert**: delete the plugin folder (KOReader goes back to its file browser) and the `KoNewspaper/` folder.

## 2026-11-01 – Change set 4: dictionaries, newspaper catalog, shelf-style newsstand

**Found**: v1 worked on the device. RaiNews, Fatto, Tgcom, BBC, Guardian and NPR were downloaded and opened, with no errors in crash.log.

**What**
- Dictionaries in `.adds/koreader/data/dict/` (from KOReader's own catalog plus FreeDict):
  - Italiano (reader.dict)
  - English (Wiktionary)
  - Italiano-English (Wiktionary)
  - English-Italiano (FreeDict 2025.11.23)
  - Long-press a word to look it up.
- `giornali.lua` is now a catalog of 26 free papers live-tested on 2026-11-01: 15 Italia, 11 Mondo.
  - Dropped for paywalls, blocked feeds or empty pages: il Post, Fanpage, Repubblica, il Giornale, Avvenire, HuffPost, manifesto, France 24, Independent, Sky News, NYT, CNN, Le Monde.
- Newsstand redesign:
  - Italia/Mondo tabs.
  - Front pages (masthead, date, top headline, photo) on 2×2 shelves with page arrows.
  - Bottom bar: I miei libri / Aggiorna / Giornali (pick papers; saved as `konewspaper_selected`).
- Builder now saves `<date>.meta.lua` + `<date>.cover.jpg|png` for the front page. Pruning also removes covers, meta files and `.sdr` folders.
- Fix: pages that aren't valid UTF-8 (Latin-1/cp1252, e.g. Corriere) are converted.

**Revert**: delete `data/dict/*` and copy the earlier plugin files back from git or this log.

## 2026-11-01 – Change set 5: light & phone buttons, repo

**What**
- Edicola header gets a **Luce** button (KOReader's frontlight dialog) and a **Telefono** button. Telefono starts the LocalSend receiver: save folder `/mnt/onboard/Libri`, device name "EdiKOla". Closing the message stops the receiver and turns Wi-Fi off.
- Fix: tile photos never showed. The 3-line headline left too little room, so headlines are now 2 lines.
- Menus: Q/W/E shortcut hints disabled.
- The project moved into this repo (`EdiKOla/`). README screenshots come from KOReader's emulator (`tools/screenshots/`).

`localsend.koplugin` v1.4.5 (armv7, kaikozlov, MIT) is installed in `plugins/`. `/mnt/onboard/Libri` was created.

**Revert**: delete `plugins/localsend.koplugin`.

## 2026-11-01 – Change set 6: pinch to zoom photos

**What**
- In an article, spreading two fingers on a photo opens it full screen. There, pinch and spread zoom it, a drag moves it, and a tap closes it. Anywhere else, pinch and spread keep KOReader's behaviour: text size in EPUBs, zoom in PDFs.

**Revert**: copy the earlier `main.lua` back from git.

## 2026-11-01 – Change set 7: clock, text size buttons, photo tap, lock screen

**What**
- Pinch and spread were unreliable on the Nia, so there are now buttons that need only one finger:
  - **A− / A+** (top-right while reading an EPUB) change the text size by 2.
  - A **tap** on a photo opens it full screen with *Original size / Rotate / Close*. Spread still works there too.
- **Clock** (HH:MM) next to the date on the Edicola, and top-centre while reading. It updates every minute and after waking up.
- **Lock screen**: `lockscreen/edikola.png` (the user's EdiKOla drawing, grayscale, 758×1024). Settings applied once under `konewspaper_defaults_v2`: `screensaver_type`=random_image, `screensaver_dir`=the plugin's `lockscreen/`, `screensaver_show_message`=false, `screensaver_img_background`=white.

**Revert**: set `screensaver_type` back to "disable" (it was "disable", with `screensaver_show_message`=true and `screensaver_img_background`=black). Copy the earlier `main.lua` back from git.

## 2026-11-02 – Change set 8: Buone notizie and Scienza e tecnologia shelves

**What**
- `plugins/konewspaper.koplugin` updated (it was the previous `master` version).
  - Two new shelves, **Buone notizie** and **Scienza e tecnologia**, next to Italia and Mondo. The catalog has
    45 papers. All 20 on the new shelves are defaults.
  - Applied once at the next start: `konewspaper_defaults_v4` adds those 20 papers to `konewspaper_selected`.
    The 10 papers already chosen stay.
- The custom OS work (Nickel-free boot, turning off unused KOReader plugins) stays on `dev`. None of it is on the device.

**Backup**: `backup/2026-11-02_shelves/` (old plugin + `settings.reader.lua`).

**Revert**: copy both back from the backup.
