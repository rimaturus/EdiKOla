# EdiKOla on the Bigme B6 Pro Color

The `bigme-main` branch: the same newsstand as on the Kobo, in color, with pen notes on every article.
The Bigme runs Android 14, so EdiKOla runs on the official **KOReader app for Android**; nothing in the
Bigme's system is changed. This guide is written before the device arrived (the parts marked
**to check** are untested), and every step ends with a **Check**.

About 20 minutes.

**You need**: the Bigme with its pen, its USB-C cable, a computer, Wi-Fi (or the Bigme's 4G), and this
repository on the `bigme-main` branch.

## What's different from the Kobo

| | Kobo Nia | Bigme B6 Pro Color |
|---|---|---|
| Screen | 6", 212 ppi, grayscale | 6", Kaleido 3: 300 ppi text, 150 ppi color |
| Newspaper shelves | black mastheads | each shelf has its color (Italia red, Mondo blue, Buone notizie green, Scienza purple) |
| Photos and covers | gray | color |
| Sommario | list | big cards, a colored stripe per topic |
| Top-right button | Telefono (LocalSend) | **Appunti**: the notebook |
| While reading | Edicola, Titoli, A− A+ | the same, plus **Appunti**: a sheet for this article |
| Wi-Fi | EdiKOla turns it on and off | Android's: Wi-Fi or 4G, whichever is on |
| Updates | 4 papers at a time | 8 at a time (8 cores, 8 GB) |
| Start-up | Kobo boots straight into the Edicola | open the KOReader app (see step 5) |
| Books from the phone | Telefono button (LocalSend plugin) | the LocalSend app on the Bigme, saving into `Libri` |

So far nothing in the Bigme's system is changed: Android starts in seconds and runs KOReader next to its own
apps. The plan to go further (backup, ADB debloat, root, a custom ROM only if it keeps the pen and the 75 FPS
e-ink driver that live in Bigme's firmware) is in [CLAUDE.md](../CLAUDE.md); each system change will be
logged, with its revert, in `bigme/CHANGES.md`.

## 1. Build the files (on the computer)

```sh
sh bigme/build.sh out-bigme
```

It downloads KOReader for Android (v2026.07.1, arm64; the build checks its SHA-256) and writes:
- `out-bigme/KOReader.apk`: the app;
- `out-bigme/koreader/`: EdiKOla (`plugins/konewspaper.koplugin`) and `patches/2-edikola-bigme.lua`.

**Check**: both are there.

## 2. Install KOReader

1. Connect the Bigme to the computer with USB, and on the Bigme pick **File transfer** in the USB notification.
2. Copy `KOReader.apk` into the Bigme's `Download` folder.
3. On the Bigme open **Files**, then `Download`, then tap `KOReader.apk`. Allow installing from this source
   when Android asks.
4. Open **KOReader** once and allow access to files (KOReader needs it to keep its folder on the internal
   storage). Then close it.

**Check**: the internal storage has a `koreader` folder.

(KOReader is also on F-Droid and Google Play; either works, the plugin is the same.)

## 3. Add EdiKOla

1. Copy the `out-bigme/koreader` folder onto the root of the Bigme's internal storage. It merges with the
   `koreader` folder KOReader made: Windows asks whether to merge, say yes.
2. Open KOReader.

**Check**: the Edicola appears, with colored mastheads. (A message may say documents are now in color: tap it.)
The patch turns color on for any Android device, since this package is only for the Bigme; the
color rendering option in KOReader's screen menu (**Schermo**) switches it off again.

## 4. Tune the Bigme for KOReader (to check: names follow Bigme's E-Ink Center)

Bigme refreshes the e-ink screen itself, per app. For writing, EdiKOla switches KOReader to E-Ink Center's
low-latency handwriting mode while a notes sheet is open, and back to the reading mode when it closes
(step 6). For reading, in **E-Ink Center** (swipe down from the top, or the floating button), pick
**KOReader** and set:
- **Refresh mode**: the clear/"Default" mode for reading, a faster one if page turns feel slow;
- **Color**: saturation one step up if photos look washed out (Kaleido colors are soft);
- **Auto-refresh**: about every 6 pages, to clear ghosting (KOReader can't do this on a Bigme).

In Android **Settings → Battery**, let KOReader run without restrictions: otherwise Android may stop an update
halfway when the screen goes off.

**Check**: pages turn without leftover shadows, and an "Aggiorna" with the screen off finishes.

## 5. Make it the first thing you see

Put KOReader on the Bigme's home screen, or on the dock. Android always starts on Bigme's own launcher,
so the Edicola is one tap away, not automatic.

**Check**: one tap from the home screen opens the Edicola.

## 6. Notes with the pen

- In an article, tap **Appunti** (top right): a ruled sheet opens, with the article's title on top.
  Write anywhere on the paper. The squares choose the ink (black, blue, red, green); **Gomma** erases whole
  strokes; **Annulla** undoes the last stroke or erasure; **Pulisci** clears the sheet (and **Annulla**
  brings it back). **Fine** (or Back) saves and goes back to the article.
- **Only the pen writes.** From the first time the pen touches a sheet, fingers and a resting hand don't
  draw any more (the sheet says "scrive solo la penna"); they still tap the buttons. Before that, a finger
  draws too, so a sheet works even without the pen.
- **Pressure**: pressing harder draws a thicker line.
- **Erasing with the pen**: the pen's eraser end, or the pen's side button held while writing, erases
  whole strokes, like **Gomma**.
- **Trascrivi** turns the writing into text: one line of text per ruled line you wrote on. The text appears,
  is kept with the note, and shows on its card in the notebook. The first time, EdiKOla asks before going
  on: recognition is Google's handwriting recognition (the one behind Google's handwriting keyboard), so
  this sheet's strokes are sent to Google, only the strokes, only when you tap **Trascrivi**. It needs
  internet.
- In the Edicola, **Appunti** (top right) is the notebook: every note with its picture, newest first, and
  **+ Nuovo foglio** for a free sheet. A note of an article has an **Articolo** button that opens it.
- In the Sommario, articles with a note say "con appunti".
- Notes are files in the `Appunti` folder of the internal storage: a `.png` picture of each (to copy to a
  computer), a `.txt` with its transcription, and a `.lua` file with the strokes (what EdiKOla reopens).
  Deleting them deletes the note.

**Check**: write a word with the pen, then put a finger on the paper: the finger doesn't draw. Tap
**Trascrivi**: the word comes back as text. Tap **Fine**, open **Appunti** in the Edicola: the note is there
with its picture and its text.

How the pen part works, and what is still **to check** on the device:
- KOReader's Android app drops the pen information Android gives it. EdiKOla adds it back (tool, side
  button, pressure; `knp_android.lua`). Bigme's firmware may report its pen as a finger: EdiKOla then
  recognises it by its input device, `fts_ts_pen`. If the finger still draws after the pen has written,
  `koreader/crash.log` has lines `EdiKOla: input device …` naming each device: send them to me.
- While writing, only the changed part of the screen is sent to the display, instead of the whole screen
  each time, and KOReader is in E-Ink Center's handwriting mode (1029). That mode goes through a Bigme system
  service that Android may refuse to an ordinary app: `crash.log` then says `EdiKOla: … refused` or `no Bigme
  display service`, and the pen works anyway, at the speed of the reading mode.
- Recognition is online; nothing on the device can read handwriting from inside KOReader.

## If something is off

- **Gray mastheads and photos**: color rendering is off in KOReader's screen menu (**Schermo**): turn it on.
- **"Nessuna connessione a internet"** on Aggiorna: turn on Wi-Fi or mobile data from the top of the screen.
- **"Trascrizione non riuscita"**: no internet, or Google's service didn't answer; try again later.
  Strokes are never sent unless you tap **Trascrivi**.
- **To go back to plain KOReader**: delete `koreader/plugins/konewspaper.koplugin` and
  `koreader/patches/2-edikola-bigme.lua`. Uninstalling KOReader removes everything except the `koreader`,
  `KoNewspaper`, `Libri` and `Appunti` folders.
