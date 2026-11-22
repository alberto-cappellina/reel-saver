# Deploy — Reel Saver

Due cose da distribuire:

1. **l'APK** (l'app Android)
2. (opzionale) una **pagina HTML** di download + un **`version.json`** per
   l'auto-update, ospitati su un qualsiasi hosting statico (FTP).

---

## 1. Configurazione

Copia il file di esempio e compilalo con i tuoi valori:

```bash
cp .deploy.env.example .deploy.env
```

`.deploy.env` è **gitignorato** (non finisce nel repo). Contiene:

| Variabile | A cosa serve |
|---|---|
| `UPDATE_URL` | URL del `version.json` per l'auto-update. **Vuoto = auto-update disattivato.** |
| `APK_URL` | URL pubblico diretto all'APK (scritto dentro `version.json`). |
| `ARUBA_FTP_HOST` / `ARUBA_FTP_DIR` / `ARUBA_FTP_USER` | FTP del tuo hosting. |

La **password FTP** non va nel file: si passa a runtime (`ARUBA_FTP_PASS=...`).

---

## 2. Build dell'APK

Requisiti: Flutter, Android SDK, Java 17.

Senza auto-update:

```bash
flutter build apk --release
```

Con auto-update (l'app controllerà il tuo `version.json` all'avvio):

```bash
flutter build apk --release --dart-define=UPDATE_URL="https://tuo-host/app/version.json"
```

L'APK è in `build/app/outputs/flutter-apk/app-release.apk`.

> **Firma.** La configurazione di firma sta in `android/key.properties`
> (gitignorato) + keystore `*.jks` (gitignorato). Se il file manca, la build
> ripiega automaticamente sulla *debug key*. Per generare un keystore:
> ```bash
> keytool -genkeypair -v -keystore reel-saver-release.jks \
>   -alias reelsaver -keyalg RSA -keysize 2048 -validity 10000
> ```
> poi crea `android/key.properties` con `storePassword`, `keyPassword`,
> `keyAlias=reelsaver`, `storeFile=../../reel-saver-release.jks`.
> **Mantieni sempre lo stesso keystore**, altrimenti gli aggiornamenti non si
> installano sopra la versione precedente. Fanne un **backup** (perderlo =
> niente più aggiornamenti installabili).

---

## 3. Build + version.json + upload in un comando

```bash
ARUBA_FTP_PASS="la-tua-password" ./scripts/release.sh --upload
```

Lo script: legge `.deploy.env`, builda (con `UPDATE_URL` se impostato), copia
l'APK in `site/`, rigenera `site/version.json` dal `pubspec.yaml` (usando
`APK_URL`) e carica `index.html`, `.htaccess`, `icon.png`, `version.json`,
`reel-saver.apk` sull'FTP configurato.

Senza `--upload` fa solo build + `version.json` locale (carichi tu i file di
`site/`). Le note di rilascio si impostano con `UPDATE_NOTES="• ...\n• ..."`.

> Nota hosting: su alcuni provider la cartella servita sul web è una sottocartella
> (es. `httpdocs/`, `www/`, o una cartella del dominio). Imposta `ARUBA_FTP_DIR`
> di conseguenza. `.htaccess` (Apache) fa scaricare l'APK col MIME type corretto.

---

## 4. Auto-update — come funziona

Se compilata con `UPDATE_URL`, a ogni avvio l'app scarica quel `version.json` e
confronta il `versionCode` con quello installato. Se il remoto è più alto, mostra
un **bottomsheet** che scarica e installa il nuovo APK (serve il permesso
*"Installa app sconosciute"*, richiesto da Android al primo aggiornamento).

`version.json`:

```json
{
  "versionCode": 3,
  "versionName": "1.2.0",
  "apkUrl": "https://tuo-host/app/reel-saver.apk",
  "notes": "• Novità 1\n• Novità 2"
}
```

Per pubblicare un aggiornamento: alza la versione in `pubspec.yaml`
(**incrementa sempre il numero dopo il `+`**, è il `versionCode`), poi
`./scripts/release.sh --upload`. Il `versionCode` del `version.json` non deve
mai essere più alto dell'APK realmente caricato, altrimenti il bottomsheet si
ripresenta in loop.

---

## 5. Verifica

- Apri la pagina dal telefono Android, tocca *Scarica*: deve partire il download
  dell'APK (se il browser lo apre invece di scaricarlo, controlla che `.htaccess`
  sia stato caricato — è un file nascosto).
- Installa e prova: Instagram → Condividi → Reel Saver.
- Se qualcosa va storto, in app c'è l'icona 🐞 (**Esporta log**) per ottenere il
  log diagnostico.
