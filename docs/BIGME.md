# EdiKOla on the Bigme B6 Pro Color

The `bigme` branch: the same newsstand as on the Kobo, in color, with pen notes on every article.
The Bigme runs Android 14, so EdiKOla runs on the official **KOReader app for Android**; nothing in the
Bigme's system is changed. This guide is written before the device arrived (the parts marked
**to check** are untested), and every step ends with a **Check**.

About 20 minutes.

**You need**: the Bigme with its pen, its USB-C cable, a computer, Wi-Fi (or the Bigme's 4G), and this
repository on the `bigme` branch.

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

There is no custom system on the Bigme. The Kobo needed one because Nickel took 30–40 s to start and then
had to be stopped; the Bigme's Android starts in seconds, runs KOReader next to its own apps, and replacing
its system would void the warranty and lose the pen and the 75 FPS e-ink driver, which live in Bigme's
firmware.

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
If the mastheads are gray, see "If something is off".

## 4. Tune the Bigme for KOReader (to check: names follow Bigme's E-Ink Center)

Bigme refreshes the e-ink screen itself, per app. In **E-Ink Center** (swipe down from the top, or the
floating button), pick **KOReader** and set:
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
  brings it back). **Fine** saves and goes back to the article.
- In the Edicola, **Appunti** (top right) is the notebook: every note with its picture, newest first, and
  **+ Nuovo foglio** for a free sheet. A note of an article has an **Articolo** button that opens it.
- In the Sommario, articles with a note say "con appunti".
- Notes are files in the `Appunti` folder of the internal storage: a `.png` picture of each (to copy to a
  computer) and a `.lua` file with the strokes (what EdiKOla reopens). Deleting both deletes the note.

**Check**: write a word, tap **Fine**, open **Appunti** in the Edicola: the note is there with its picture.

Limits, for now:
- KOReader on Android gets the pen as a finger: a finger on the paper draws too. Only one touch at a time
  draws, so a hand resting on the screen while the pen writes doesn't add a second line.
- No pressure (one line width) and no handwriting recognition.
- How fast the ink follows the pen depends on Bigme's refresh mode for KOReader (step 4); **to check**.

## If something is off

- **Gray mastheads and photos**: KOReader didn't recognise the Bigme. Its log (`koreader/crash.log`) has a line
  `EdiKOla: device …` with the names Android gives the device: send it to me, and the patch gets that name.
- **"Nessuna connessione a internet"** on Aggiorna: turn on Wi-Fi or mobile data from the top of the screen.
- **To go back to plain KOReader**: delete `koreader/plugins/konewspaper.koplugin` and
  `koreader/patches/2-edikola-bigme.lua`. Uninstalling KOReader removes everything except the `koreader`,
  `KoNewspaper`, `Libri` and `Appunti` folders.
