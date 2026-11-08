# Progetto: EdiKOla per Bigme B6 Pro

Questo è il branch principale del porting sul Bigme: `bigme-main` (ex `bigme`). `master` resta la versione Kobo Nia.

## Contesto
Ho un Bigme B6 Pro (Android, e-ink a colori, penna). Il sistema di serie è dispersivo come un normale telefono Android, pieno di bloatware, con una gestione della penna poco curata e una resa dei colori sotto le aspettative.

Voglio trasformarlo in una **biblioteca/edicola tascabile**: un dispositivo calmo e rilassante per leggere, fare enigmistica, prendere appunti e guardare qualche video, senza le distrazioni di uno smartphone.

## Base di partenza
- Repo: https://github.com/rimaturus/EdiKOla (plugin KOReader in Lua per Kobo Nia: edicola RSS con scaffali, articoli puliti in EPUB, sommario per argomento, catalogo di 40+ testate, ricezione file via LocalSend).
- Il branch `bigme`, che contiene il porting su questo device, è stato **rinominato in `bigme-main`** ed è il branch principale. Niente repo nuova.
- Riusa la filosofia e il codice esistenti dove possibile, invece di riscrivere da zero.

## Stato attuale
Livello 2 in corso (debloat ADB fatto prima del backup, per scelta: tocca solo `/data`); niente root, partizioni intatte. EdiKOla gira dentro l'app ufficiale KOReader per Android (`bigme/build.sh`, `bigme/patches/2-edikola-bigme.lua`), con scaffali e sommario a colori e **Appunti** a penna su ogni articolo (solo penna, pressione, gommino, trascrizione). Installazione e verifiche: [docs/BIGME.md](docs/BIGME.md).
Dati del dispositivo, ricerca su root/backup (piattaforma HiBreak Pro, MT6877): [bigme/DEVICE.md](bigme/DEVICE.md). Debloat ADB applicato (`bigme/debloat.txt` + `bigme/debloat.sh`); registro modifiche: [bigme/CHANGES.md](bigme/CHANGES.md).

## Obiettivo
Stravolgere il sistema di serie: debloat profondo via ADB/root, fino a una ROM personalizzata se fattibile. Il risultato deve essere un'esperienza pensata per l'e-ink: launcher dedicato, poche schermate, niente notifiche invadenti, refresh e contrasto ottimizzati, uso naturale della penna.

## Strategia per livelli (dal meno al più invasivo)
1. **Backup completo** del firmware originale e procedura di ripristino verificata, prima di qualsiasi modifica.
2. **Debloat via ADB** (`pm uninstall --user 0` / `pm disable-user`), con un elenco motivato dei pacchetti rimossi e uno script per ripristinarli.
3. **Root** (es. Magisk) per tutto ciò che ADB non permette: tuning dei colori e del refresh e-ink, rimozione completa delle app di sistema, launcher come app di sistema.
4. **ROM personalizzata/GSI** solo dopo aver verificato la fattibilità: bootloader sbloccabile, disponibilità dei sorgenti del kernel e, soprattutto, se si possono mantenere driver e servizi proprietari Bigme per e-ink, refresh e penna. Se una ROM fa perdere queste funzioni, meglio fermarsi al livello 3.

## Funzionalità richieste
1. **Notizie RSS** come in EdiKOla (scaffali, articoli puliti, aggiornamenti incrementali).
2. **Enigmistica con la penna**: cruciverba, sudoku, schemi liberi, ecc., scritti a mano.
3. **Libri e PDF** importabili da PC, Bluetooth, LocalSend e altri metodi semplici; annotazioni a penna sui PDF.
4. **Ambiente Linux** (es. Termux/proot o chroot con root) per usarlo come secondo PC, anche con tastiera esterna.
5. **Resa dei colori migliorata**: profili di saturazione/contrasto per l'e-ink a colori, per app o per tipo di contenuto.
6. **Video** con un profilo di refresh adatto all'e-ink.
7. Altre idee coerenti con la filosofia "calma e offline-first", ad esempio:
   - quaderno/diario a penna con esportazione in PDF;
   - Wikipedia e dizionari offline (es. Kiwix);
   - fumetti (CBZ/CBR) e riviste;
   - podcast e audiolibri;
   - schermata di blocco con meteo/citazione del giorno, come in EdiKOla.

## Regole di lavoro
- Prima di scrivere codice, controlla se esiste già un'app, un modulo Magisk o un progetto open source che fa la stessa cosa (KOReader per Android, Kiwix, Termux, LocalSend, liste di debloat esistenti…) e integralo invece di reinventarlo.
- Approccio YAGNI: scrivi solo il codice necessario, niente funzioni superflue. La soluzione più semplice è di solito la migliore.
- Ogni modifica al sistema deve essere reversibile e documentata in `bigme/CHANGES.md` (stesso formato di `CHANGES.md` del Kobo: data, cosa trovato, cosa fatto, **Revert** con i comandi per annullarla).
- Prima di qualsiasi operazione a rischio di brick (sblocco del bootloader, flash, modifiche a `/system` o `/vendor`), spiegami i rischi e aspetta la mia conferma.
- Se qualcosa non è chiaro, chiedimi prima di procedere.
