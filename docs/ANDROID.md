# EdiKOla per Android (app nativa)

Il branch `Android` contiene `app-android/`, EdiKOla come app Android vera (Kotlin + Jetpack Compose), senza
KOReader. Per il telefono è la strada giusta: KOReader è fatto per gli e-reader (luminosità sua, tasti del
volume che girano pagina, notte = colori invertiti, niente audio in background).

## Cosa fa

- **Edicola**: gli scaffali Italia, Mondo, Buone notizie, Scienza; ogni giornale con la prima pagina di oggi
  (titolo e foto). **Aggiorna** (in alto) scarica tutti i giornali scelti, 6 alla volta; un giornale mai
  scaricato si scarica toccandolo. **Ingranaggio**: scegli i giornali (lo stesso catalogo di `giornali.lua`).
- **Lettore**: articoli puliti (solo testo e foto), A− A+, articolo precedente e successivo, una foto toccata
  si apre a schermo intero con lo zoom.
- **Sommario**: le notizie di oggi di tutti i giornali, per argomento; quelle inglesi con titolo e riassunto in
  italiano.
- **Ascolta**: legge il giornale ad alta voce come un audiolibro, tutto sul telefono (sherpa-onnx con le voci
  Piper Paola per l'italiano e Alba per l'inglese, scelte articolo per articolo). Suona come un contenuto
  multimediale: altoparlante, tasti del volume, controlli nella notifica e sulla schermata di blocco, continua a
  schermo spento e in altre app, si ferma per una chiamata o se stacchi le cuffie. Dal lettore, **▶** legge
  dall'articolo aperto.
- **Giochi** (La Settimana di EdiKOla): cruciverba del giorno con le definizioni dai titoli di oggi,
  crucipuzzle con la chiave, sudoku facile, medio, difficile. Ogni mossa è salvata.
- **Libri**: EPUB e PDF, da **Aggiungi** o condivisi da un'altra app (LocalSend, browser, posta). L'EPUB si
  legge come gli articoli, il PDF pagina per pagina (due dita per lo zoom). Riprende dove eri rimasto.
- **Penna** (S Pen o altro pennino): scrive direttamente su articoli, libri e PDF; le dita scorrono e toccano
  come sempre. Gommino o tasto della penna cancellano il tratto, la pressione ingrossa la linea. La matita in
  alto: colore, annulla, cancella gli appunti.
- **Luminosità**: quella di sistema. **Tema scuro**: segue quello di Android.

## Installare

Dal telefono apri https://github.com/rimaturus/EdiKOla/releases/tag/android-latest, scarica
`EdiKOla-android.apk` e aprilo (consenti l'installazione dal browser). Gli aggiornamenti si installano sopra.
È un'app a sé (`it.rimaturus.edikola`): non tocca KOReader né il Bigme.

## Come si compila

GitHub Actions (`.github/workflows/android.yml`) a ogni push su `Android` che tocca `app-android/`:
1. `app-android/fetch-native.sh` scarica (SHA-256 fissati) sherpa-onnx v1.13.6 per Android e le due voci
   (int8, circa 18 MB l'una) con i dati di espeak-ng solo per italiano e inglese;
2. `gradle assembleRelease` (AGP 8.7, Kotlin 2.1, Compose BOM 2024.12, media3 1.5, jsoup, coil);
3. pubblica l'APK nella pre-release `android-latest`;
4. prova l'app su un emulatore Pixel 6 (`app-android/ci-smoke.sh`): aggiorna i giornali, fa partire Ascolta,
   apre un articolo, i giochi, i libri, il tema scuro; screenshot, albero dell'interfaccia e log finiscono nel
   branch `ci-report` insieme al log della compilazione.

In locale: `sh app-android/fetch-native.sh`, poi apri `app-android/` con Android Studio.

La chiave di firma `app-android/edikola.jks` è nel repo (pubblica): serve solo perché gli aggiornamenti si
installino sopra. Per una chiave tua: secret `EDIKOLA_KEYSTORE` (percorso) e `EDIKOLA_KEYSTORE_PASSWORD`.

## Il codice

| File | |
|---|---|
| `Catalog.kt`, `Topics.kt`, `ParoleData.kt` | catalogo, argomenti del Sommario, parole dei giochi (da `giornali.lua`, `knp_topics.lua`, `knp_parole.lua`) |
| `Extract.kt` | RSS/Atom e estrazione dell'articolo (port di `knp_extract.lua`, con jsoup) |
| `Store.kt`, `Repo.kt` | download, cache degli articoli, edizioni (JSON per giornale e giorno, ultime 3), stato dell'app |
| `Testo.kt`, `Ascolta.kt` | lingua per articolo, pezzi da leggere, WAV; voci sherpa-onnx e `AscoltaService` (media3) |
| `Giochi.kt`, `GiochiUi.kt` | generatori (port di `knp_sudoku`, `knp_crucipuzzle`, `knp_cruciverba`) e schermate |
| `Libri.kt`, `Reader.kt`, `Ink.kt` | libri EPUB/PDF, lettore, penna |
| `Home.kt`, `Player.kt`, `Theme.kt`, `MainActivity.kt` | schermate e colori (chiari e scuri) |
| `com/k2fsa/sherpa/onnx/Tts.kt` | API Kotlin di sherpa-onnx v1.13.6 (Apache-2.0), deve corrispondere alla libreria |

Voci: Paola (`it_IT-paola-medium`, licenza del dataset alla sua pagina) e Alba (`en_GB-alba-medium`, CC BY 4.0),
del progetto Piper, convertite da sherpa-onnx.
