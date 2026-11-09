# EdiKOla on the Bigme B6 Pro Color

The `bigme-main` branch: the same newsstand as on the Kobo, in color, with the pen writing straight on
articles and books, and **La Settimana di EdiKOla**, free puzzles made on the device.
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
| Top-right button | Telefono (LocalSend) | **Giochi**: La Settimana di EdiKOla |
| While reading | Edicola, Titoli, A− A+ | the same, plus **Prossimo** (next paper of the shelf) and **Penna**: the pen writes on the page |
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
low-latency handwriting mode while the pen writes, and back to the reading mode 3 s after it lifts
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

## 6. Write with the pen

- **The pen writes straight on the page** you are reading, a newspaper article or a book: underline,
  circle, write in the margin. Nothing to open or switch on.
- **Fingers don't write**: they turn pages, follow links and open photos as before. The pen on the top bar
  still taps its buttons.
- **Pressure**: pressing harder draws a thicker line.
- **Erasing**: the pen's eraser end, or the pen's side button held while writing, erases whole strokes.
- **Penna** (top right, in the current ink's color): the ink (black, blue, red, green), **Annulla l'ultimo
  tratto**, **Cancella la pagina**.
- Ink belongs to its page and comes back when you return to it, with the same text size (a page is known by
  where it starts in the text: with another text size the pages start elsewhere, and the ink shows up again
  once the size is back). It is kept per document in the `Appunti` folder of the internal storage, one
  `.lua` file each.

**Check**: write a word on an article with the pen, then swipe with a finger: the page turns and nothing is
drawn. Swipe back: the word is there. Close and reopen the paper: still there.

How the pen part works:
- KOReader's Android app drops the pen information Android gives it. EdiKOla adds it back (tool, side button,
  pressure; `knp_android.lua`). Bigme's firmware may report its pen as a finger: EdiKOla then recognises it by
  its input device, `fts_ts_pen`.
- Android hands over a moving pen about 60 times a second, each time with the positions in between; KOReader
  only reads the last one, which turns a curve into a chain of straight bits. EdiKOla passes every in-between
  position on, so the line follows the pen.
- Each bit of stroke is drawn straight into the screen and only its rectangle is sent to the display, and
  KOReader is in E-Ink Center's handwriting mode (1029) while the pen works. Checked on the Bigme on
  2026-11-09: `crash.log` / logcat show `EdiKOla: E-Ink Center mode 178 -> 1029` at the first pen touch and
  back to 178 three seconds after it lifts.
- Bigme's own notes app is faster still: it draws through Bigme's handwriting service
  (`com.xrz.IHandwrittenService`), which paints the pen's trace itself above the app. Using it needs a client
  written in Java (a binder callback and shared memory buffers), which a KOReader plugin cannot provide: that
  would take a small companion app.

## 7. La Settimana di EdiKOla (Giochi)

**Giochi**, top right in the Edicola, opens the puzzle magazine: everything is made on the Bigme, free and
offline, and every move is saved at once (`koreader/settings/edikola_giochi.lua`), so a puzzle waits where it
was left until it is solved or **Nuovo** starts another.
- **Cruciverba del giorno**: a "schema libero" crossword. Many clues are the day's headlines with the answer
  blanked out, the rest come from a dictionary of definitions written for EdiKOla. Tap a square to choose it
  (tap again to switch across/down), type on the keyboard below. **Definizioni** lists every clue,
  **Controlla** turns wrong letters red, **Aiuto** fills in the square.
- **Crucipuzzle**: tap the first and the last letter of a word in the grid; each word found takes its own
  color. When all are found, the letters left over, read in order, spell the key.
- **Sudoku** facile, medio, difficile: always one solution. Tap a square, then a number; **Controlla**,
  **Aiuto**, **Cancella**.

**Check**: open Giochi, solve a word of the crossword, close it: the cover says how many squares are left.

## If something is off

- **Gray mastheads and photos**: color rendering is off in KOReader's screen menu (**Schermo**): turn it on.
- **"Nessuna connessione a internet"** on Aggiorna: turn on Wi-Fi or mobile data from the top of the screen.
- **To go back to plain KOReader**: delete `koreader/plugins/konewspaper.koplugin` and
  `koreader/patches/2-edikola-bigme.lua`. Uninstalling KOReader removes everything except the `koreader`,
  `KoNewspaper`, `Libri` and `Appunti` folders.
