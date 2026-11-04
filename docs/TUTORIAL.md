# First installation, step by step

This guide takes a Kobo from the box (or from a factory reset) to EdiKOla starting by itself when the Kobo
is switched on. It follows what worked on a Kobo Nia with firmware 4.38. Each step ends with a **Check**:
don't go on until it passes.

About 45 minutes, most of it waiting for downloads and restarts.

**You need**
- A Kobo e-reader and its USB cable, a computer (these steps use Windows), and a Wi-Fi network.
- This repository: on GitHub, **Code → Download ZIP**, then unzip it. Or `git clone https://github.com/rimaturus/EdiKOla.git`.

> **The one rule:** before unplugging the Kobo, always eject it first (Windows: right-click the drive →
> **Eject**, and wait for "Safe to remove"). Unplugging without ejecting once lost the whole KOReader
> install on this project's Kobo (`CHANGES.md`, change set 0b).

## 1. Set up the Kobo

1. Switch it on and follow the setup: language, Wi-Fi, Kobo account.
2. If it offers a software update, let it install and restart. It may do so without asking.

**Check**: you reach the Kobo home screen ("Home") and can open a book.

## 2. Connect it and make a backup

1. Plug the Kobo into the computer and tap **Connect** on its screen. A drive called `KOBOeReader` appears.
2. Copy the hidden `.kobo` folder from the drive to a folder on your computer, e.g. `backup/<today>/`.
   If anything goes wrong later, this holds the Kobo's settings and library database.

**Check**: the backup folder holds `.kobo/Kobo/Kobo eReader.conf`.

## 3. Install KOReader

1. Download the latest **OCP-KOReader** zip from the
   [one-click install thread](https://www.mobileread.com/forums/showthread.php?t=314220) on MobileRead.
   It contains KOReader, plus NickelMenu to start it.
2. Extract the zip to the root of the Kobo drive. Windows asks about merging the `.kobo` folder: say yes.
   You now have `.adds/koreader/`, `.adds/nm/` and `.kobo/KoboRoot.tgz` on the drive.
3. Open `.kobo/Kobo/Kobo eReader.conf` in Notepad. Under the `[FeatureSettings]` section (add the
   section at the end if it isn't there), add this line:

   ```
   ExcludeSyncFolders=(\\.(?!kobo|adobe).+|([^.][^/]*/)+\\..+)
   ```

   It stops the Kobo from listing KOReader's own files as books.
4. Eject the Kobo and unplug it. It shows an update screen, installs the package and restarts.

**Check**: the home screen has a new **NickelMenu** entry (bottom right, or under **More**), and in it,
**KOReader**. Tap it: KOReader opens. Close it again from its menu (top of the screen → **Exit**).

> **No KOReader entry, or NickelMenu shows an error?** Connect the Kobo again. In `.adds/nm/koreader`,
> remove the `#` at the start of the line that ends in `koreader.sh`. In `.adds/nm/kfmon`, put a `#` in
> front of `generator : main : kfmon`. Eject. This starts KOReader directly, without KFMon
> (`CHANGES.md`, change set 0c).

## 4. Add EdiKOla

1. Connect the Kobo. Copy the `konewspaper.koplugin` folder from this repository into
   `.adds/koreader/plugins/` on the drive.
2. For the **Telefono** button: download the Kobo (armv7) release of
   [localsend.koplugin](https://github.com/kaikozlov/localsend.koplugin/releases) and put its
   `localsend.koplugin` folder in the same `plugins/` folder.
3. Eject, then start KOReader from NickelMenu.

**Check**: instead of KOReader's file list, you see the **Edicola**: the clock at the top, the shelves
(Italia, Mondo, Buone notizie, Scienza e tecnologia) and the buttons at the bottom. The first time, the
shelves are empty: nothing has been downloaded yet.

EdiKOla has also changed some KOReader settings, once: text size 26, Wi-Fi turned on and off without
questions, the EdiKOla lock screen, and the page counter at the bottom of articles.

## 5. Choose the papers and download them

1. Tap **Giornali**, tick the papers you want, and close the list. A selection of each shelf is already
   ticked.
2. Tap **Aggiorna**. Wi-Fi turns on by itself. The first time, KOReader may ask you to pick the network
   and type its password; after that it connects without asking.
3. Wait. The first update downloads every article, so it takes a while (several minutes with 30 papers).
   The message shows how many papers are ready. Later updates only fetch new articles and are much faster.

**Check**: the **Sommario** opens by itself, in Italian: one entry per topic with its main headlines. Tap a
topic to see its articles, each with its opening sentences; ✕ (top right) goes back. Close the Sommario:
the shelves show front pages (masthead, date, headline, photo). Wi-Fi is off again.

## 6. Read a paper

1. Tap a front page. The edition opens on its front page with the list of headlines.
2. Tap the right side of the screen to go forward, the left side to go back. Tap a headline to jump to it.
3. At the bottom you see, for example, **18/40 (1/5)**: page 18 of 40 in the paper, page 1 of 5 of this article.
4. **A− / A+** at the top right change the text size. Tap a photo to see it full screen.
5. **Titoli**, next to it, goes back to the front page with the headlines. **◀ Edicola** at the top left goes
   back to the newsstand.

**Check**: all of the above works. Long-press a word: a dictionary window opens (it may say no
dictionary is installed; see step 8).

## 7. Start straight into EdiKOla

So far EdiKOla starts from NickelMenu. To have it open by itself every time the Kobo is switched on:

1. Connect the Kobo. Make sure `.kobo/KoboRoot.tgz` is **gone**: the Kobo deletes it once installed (step 3).
   If it is still there, eject and restart the Kobo first, or you would overwrite the KOReader package.
2. Copy `autoboot/KoboRoot.tgz` from this repository into `.kobo/` on the drive.
3. Eject. The Kobo installs it and restarts.

**Check**: switch the Kobo off and on again (hold the power button → **Power off**). The Kobo home screen
appears for a few seconds, then the Edicola opens by itself.

- To skip it for one start, create an empty file `.adds/noautoboot` on the drive (delete it to turn
  autostart back on).
- Leaving KOReader (its menu → **Exit**) brings back the normal Kobo home screen until the next restart.

## 8. Optional extras

- **Dictionaries**: long-press the top bar of the Edicola. It closes and shows KOReader's file browser,
  with KOReader's menu at the top of the screen. Open the search menu (magnifying glass) → dictionary
  settings → **Download dictionaries**, and pick the ones you want; this project uses Italian (reader.dict),
  English and Italian–English (Wiktionary). Restart KOReader to get the Edicola back.
- **Phone**: install the free [LocalSend](https://localsend.org) app on the phone. On the Kobo tap
  **Telefono**, then on the phone share a file → LocalSend → **EdiKOla**. It lands in **I miei libri**.
- **Light**: **Luce** sets the brightness and warmth of the front light.

## 9. Handing it over

A quick run-through for the person who will use it:

- Switch on → the Edicola. Tap a paper → read. Tap right/left to turn the page. **◀ Edicola** to go back.
- **Aggiorna** fetches today's news (needs the home Wi-Fi).
- **A− / A+** for the text size, **Luce** for the light.
- The number at the bottom says where you are: **18/40 (1/5)**.

## If something goes wrong

| Problem | What to do |
|---|---|
| KOReader files disappeared after unplugging | The Kobo wasn't ejected. Redo step 3, then eject properly. |
| The Edicola stopped opening by itself after a Kobo software update | The update removed the autostart. Redo step 7 (and step 3 if NickelMenu is gone too). |
| One paper fails to download | Its site was slow or changed. The others are not affected; try **Aggiorna** later. |
| You want the plain Kobo back | Create `.adds/noautoboot`, or delete `.adds/koreader/plugins/konewspaper.koplugin`. To undo everything: on the Kobo, **Settings → Device information → Factory reset**. |

Every change made to this project's Kobo is listed in `CHANGES.md`, with how to undo it.
