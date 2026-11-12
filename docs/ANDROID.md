# EdiKOla on an Android phone

The `Android` branch: the same EdiKOla as on the Bigme (`bigme-main`), packed as one APK for a phone.
`EdiKOla.apk` is the official KOReader for Android (v2026.07.1, arm64) with EdiKOla already inside: install it
and the Edicola is there, nothing to copy.

## Build (on the computer)

```sh
sh android/build.sh out-android
```

Needs `curl`, `7z`, `zip` and Java. The downloads (KOReader, uber-apk-signer) are pinned by SHA-256. The first
run makes a signing key in `~/.config/edikola/android.jks` (other path: `KEYSTORE=...`): **keep it**, Android
only installs an update over the app if it is signed with the same key.

**Check**: `out-android/EdiKOla.apk` is there.

## Install (on the phone)

1. The app is KOReader with another signature, under KOReader's own id (`org.koreader.launcher`): if the
   official KOReader is installed, uninstall it first (its `koreader` folder stays, with settings and books).
2. Copy `EdiKOla.apk` to the phone (USB, LocalSend, ...) and open it; allow installing from that app.
3. Open **KOReader** and allow access to all files (EdiKOla keeps `KoNewspaper`, `Libri`, `Appunti` on the
   internal storage).

**Check**: the Edicola opens; **Aggiorna** downloads the papers.

## Differences from the Bigme

- No `2-edikola-bigme.lua` patch: a phone screen is color for KOReader already.
- The pen part (`knp_android.lua`) works with any Android stylus (e.g. S Pen); E-Ink Center's handwriting
  mode is Bigme only and is skipped (a line in `crash.log`, nothing else).
- KOReader's own update check offers official builds: they don't install over this one (other signature).
  Update by rebuilding and installing the new `EdiKOla.apk`.
