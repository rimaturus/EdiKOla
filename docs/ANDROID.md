# EdiKOla per Android (app nativa)

Il branch `Android` contiene `app-android/`, EdiKOla come app Android vera (Kotlin + Jetpack Compose), senza
KOReader. Per il telefono è la strada giusta: KOReader è fatto per gli e-reader (luminosità sua, tasti del
volume che girano pagina, notte = colori invertiti, niente audio in background).

## Cosa fa

Tre schede: **Oggi**, **Radio**, **Giochi e libri**.

- **Oggi**, all'apertura del giorno si aggiorna da solo (poi con ↻ in alto). Due viste:
  - **Per argomento**: la stessa notizia raccontata da più giornali compare una volta sola. In cima **In primo piano**,
    la notizia riportata da più giornali (non più la prima scaricata), poi **Le notizie del giorno** (le altre che
    escono su più testate) e un argomento dopo l'altro (Politica, Economia e lavoro, Esteri…), con «Altre N notizie».
    Gli argomenti li assegna **Gemini Nano**, il modello linguistico dentro il telefono (Galaxy S25 e simili, ML Kit
    Prompt API): tutto resta sul telefono. Dove Nano non c'è, li assegnano le parole chiave di `Topics.kt`.
  - **Per giornale**: gli scaffali (Italia, Mondo, Buone notizie, Scienza), ogni giornale con i primi titoli; toccandolo
    si apre la sua edizione, con le cuffie per ascoltarla.
  L'ingranaggio sceglie i giornali. Sezioni: Italia, Mondo, Buone notizie, Scienza, Ingegneria (IEEE Spectrum, Hackaday,
  EE Times, New Atlas, Elettronica News, Interesting Engineering, Electrek, Tom's Hardware). Preselezionati 21
  giornali aggiornati ogni giorno: politica, geopolitica ed economia (RaiNews, Il Post, Corriere, Formiche, Startmag,
  BBC, Guardian, DW, Politico Europe, War on the Rocks), scienza (ANSA Scienza, Guardian Science, Ars Technica,
  Media Inaf, Quanta), ingegneria (i primi cinque) e una fonte di buone notizie (Reasons to be Cheerful). Quando la
  preselezione cambia (`CATALOG` in `Catalog.kt`), gli scaffali ripartono da quella nuova.
- **Lettore**: un articolo per pagina, si passa al successivo scorrendo di lato (o con «Prossima notizia» in fondo),
  nello stesso ordine di Oggi. In alto solo: indietro, «Aa» per la grandezza del testo, le cuffie (ascolta da qui), la
  penna. Una foto toccata si apre a schermo intero con lo zoom.
- **Radio EdiKOla**: Giulia e Marco raccontano le notizie di oggi come un programma radiofonico: sigla, apertura con le
  notizie principali, la notizia d'apertura, poi un argomento dopo l'altro (uno stacco musicale a ogni cambio), per
  ogni notizia un botta e risposta con domande, contesto e un commento, i saluti e la sigla. Durata 5–30 minuti. La
  scrive Gemini Nano sul telefono, una notizia alla volta mentre la precedente è già in onda, solo con i fatti degli
  articoli; sullo schermo si legge la battuta che stanno dicendo. Nano risponde solo con EdiKOla aperta: se esci
  dall'app, le notizie che mancano le scrive EdiKOla (più semplici) e la radio va avanti. Senza Nano: Gemini online con
  una chiave gratuita (ingranaggio), altrimenti EdiKOla. Le voci sono sul telefono (sherpa-onnx, Piper: Paola per
  Giulia, Riccardo per Marco). Sigla e stacchi sono generati dall'app.
- **Leggimi le notizie** (nella scheda Radio): gli articoli di oggi interi, uno dopo l'altro, come un audiolibro
  (Paola in italiano, Alba per l'inglese). Suona come un contenuto multimediale: tasti del volume, controlli nella
  notifica e sulla schermata di blocco, continua a schermo spento.
- **Parole inglesi**: le voci italiane le dicono all'italiana, «Nature» come «nèiciur» e non «natùre», «Google» come
  «gùgol». `app/src/main/assets/inglese.tsv` (circa 20.000 parole inglesi rare in italiano, ciascuna riscritta come la
  legge un italiano) è generato da `tools/pronuncia.py` a partire da CMUdict; le sigle in maiuscolo restano come sono.
- **Giochi** (La Settimana di EdiKOla): cruciverba del giorno con le definizioni dai titoli di oggi, crucipuzzle,
  sudoku facile, medio, difficile, kakuro facile (7×7) e kakuro (9×9), generati sul telefono con una sola soluzione
  (nel kakuro, se le somme da sole non bastano, qualche cifra è già scritta, come sulle riviste). Niente controlli e
  niente soluzioni. Due modi di compilare, scelti in alto e ricordati per tutti i giochi: **Penna**, si scrive sullo
  schema con la penna o con il dito e il tratto resta tratto (niente riconoscimento delle lettere; Gomma, Annulla);
  **Tastiera**, si tocca una casella e si scrive (nel cruciverba si va avanti lungo la parola, un secondo tocco cambia
  direzione e sopra le definizioni compare quella della parola). La S Pen scrive in entrambi i modi. Il crucipuzzle è
  solo a penna. «Nuovo» cambia schema.
- **Libri**: EPUB e PDF, da **Aggiungi** o condivisi da un'altra app (LocalSend, browser, posta). Riprende dove eri.
- **Penna** (S Pen): scrive anche su articoli, libri e PDF; lì le dita scorrono e toccano come sempre.
- **Foto**: stanno nella memoria privata dell'app (la galleria non le vede) e a ogni aggiornamento restano solo quelle
  dell'ultima edizione; quelle di un giornale tolto dagli scaffali spariscono al primo aggiornamento.
  Se in galleria vedi ancora foto di giornali, vengono dal vecchio EdiKOla dentro KOReader (cartella `KoNewspaper`):
  disinstalla KOReader dal telefono e cancella quella cartella.
- **Luminosità** di sistema, **tema scuro** quello di Android. Caratteri: Playfair Display per le testate e i titoli,
  Literata per il testo.

## Installare

Dal telefono apri https://github.com/rimaturus/EdiKOla/releases/tag/android-latest, scarica
`EdiKOla-android.apk` e aprilo (consenti l'installazione dal browser). Gli aggiornamenti si installano sopra.
È un'app a sé (`it.rimaturus.edikola`): non tocca KOReader né il Bigme.

## Come si compila

GitHub Actions (`.github/workflows/android.yml`) a ogni push su `Android` che tocca `app-android/`:
Lo stesso workflow gira sui branch `android-*` (prove): compila e prova sull'emulatore senza pubblicare l'APK.

1. `app-android/fetch-native.sh` scarica (SHA-256 fissati) sherpa-onnx v1.13.6 per Android e le due voci
   (int8, circa 18 MB l'una) con i dati di espeak-ng solo per italiano e inglese;
2. `gradle assembleRelease` (AGP 8.7, Kotlin 2.3, Compose BOM 2024.12, media3 1.5, jsoup, coil, ML Kit GenAI Prompt);
3. pubblica l'APK nella pre-release `android-latest`;
4. prova l'app su un emulatore Pixel 6 (`app-android/ci-smoke.sh`): Oggi nelle due viste, il lettore, la radio (sull'emulatore
   senza Nano, quindi scritta da EdiKOla), Leggimi le notizie, i giochi scritti col dito, i libri, il tema scuro; screenshot, albero dell'interfaccia e log finiscono nel
   branch `ci-report` insieme al log della compilazione.

In locale: `sh app-android/fetch-native.sh`, poi apri `app-android/` con Android Studio.

La chiave di firma `app-android/edikola.jks` è nel repo (pubblica): serve solo perché gli aggiornamenti si
installino sopra. Per una chiave tua: secret `EDIKOLA_KEYSTORE` (percorso) e `EDIKOLA_KEYSTORE_PASSWORD`.

## Il codice

| File | |
|---|---|
| `Catalog.kt`, `Topics.kt`, `ParoleData.kt` | catalogo, argomenti a parole chiave, parole dei giochi (da `giornali.lua`, `knp_topics.lua`, `knp_parole.lua`) |
| `Extract.kt` | RSS/Atom e estrazione dell'articolo (port di `knp_extract.lua`, con jsoup) |
| `Store.kt`, `Repo.kt` | download, cache degli articoli, edizione (JSON per giornale, solo l'ultima), stato dell'app |
| `Notizie.kt` | le storie di oggi: articoli uguali di giornali diversi insieme, ordine d'importanza, argomenti |
| `Llm.kt` | il modello linguistico: Gemini Nano (ML Kit Prompt API), o Gemini online con la chiave |
| `Radio.kt` | Radio EdiKOla: scaletta, battute scritte dal modello (o da EdiKOla), sigle |
| `Testo.kt`, `Ascolta.kt`, `Pronuncia.kt` | pezzi da leggere, WAV e sigle; voci sherpa-onnx e `AscoltaService` (media3); parole inglesi all'italiana |
| `Giochi.kt`, `GiochiUi.kt` | generatori (port di `knp_sudoku`, `knp_crucipuzzle`, `knp_cruciverba`) e schemi da scrivere |
| `Libri.kt`, `Reader.kt`, `Ink.kt` | libri EPUB/PDF, lettore a pagine, penna |
| `Home.kt`, `Player.kt`, `Theme.kt`, `MainActivity.kt` | Oggi, Radio, Giochi e libri, impostazioni; colori (chiari e scuri) |
| `tools/pronuncia.py` | genera `assets/inglese.tsv` (CMUdict, BSD; scelta delle parole con le frequenze di FrequencyWords/OpenSubtitles) |
| `com/k2fsa/sherpa/onnx/Tts.kt` | API Kotlin di sherpa-onnx v1.13.6 (Apache-2.0), deve corrispondere alla libreria |

Voci: Paola (`it_IT-paola-medium`, licenza del dataset alla sua pagina), Riccardo (`it_IT-riccardo-x_low`) e Alba
(`en_GB-alba-medium`, CC BY 4.0),
del progetto Piper, convertite da sherpa-onnx.
