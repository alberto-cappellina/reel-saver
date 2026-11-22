<div align="center">
  <img src="assets/icon/icon.png" width="96" alt="Reel Saver" />
  <h1>Reel Saver</h1>
  <p>App Android (Flutter) per scaricare reel/post <b>pubblici</b> di Instagram,
  salvarli in galleria e ricondividerli su Telegram / WhatsApp.</p>
</div>

---

> [!WARNING]
> **Uso personale ed educativo.** Instagram non offre un'API ufficiale di
> download e questo progetto non è affiliato né approvato da Instagram/Meta.
> Scarica **solo** contenuti pubblici e **solo** se hai il diritto di salvarli,
> nel rispetto del copyright degli autori e dei
> [Termini di Instagram](https://help.instagram.com/581066165581870). Scaricare
> contenuti altrui può violare tali termini: la responsabilità dell'uso è di chi
> utilizza l'app.

## Funzionalità

- Compare nel menu **Condividi** di Instagram (share intent `text/*`).
- Riceve l'URL del reel/post (oppure lo incolli a mano).
- **Scarica il video** come file `.mp4` unico (H.264 + audio), pronto da condividere.
- Lo **salva in galleria** (album *Reel Saver*).
- Lo **ricondivide** su Telegram, WhatsApp, ecc. con un tap.
- **Auto-update opzionale**: se configurata con un *update URL*, all'avvio
  verifica se c'è una versione più recente e la propone in un bottomsheet.
- **Log diagnostico esportabile** (icona 🐞) per capire eventuali errori.

## Come funziona (architettura)

Tutto **lato client, senza backend**:

- [`lib/services/instagram_resolver.dart`](lib/services/instagram_resolver.dart)
  — da un URL Instagram ricava il link diretto al video. Stabilisce una sessione
  (cookie) e scarica la pagina `/p/{shortcode}/` con header da browser
  (`Sec-Fetch-Mode: navigate`), poi estrae le `video_versions` dai blocchi
  `data-sjs`. Fallback: endpoint GraphQL e `api/v1/media/{id}/info/`.
- [`lib/services/download_service.dart`](lib/services/download_service.dart) —
  download con avanzamento (`dio`) + salvataggio in galleria (`gal`).
- [`lib/services/update_service.dart`](lib/services/update_service.dart) —
  auto-update via un `version.json` remoto (attivo solo se `UPDATE_URL` è
  impostato a build-time).
- [`lib/main.dart`](lib/main.dart) — UI, ricezione share (`receive_sharing_intent`),
  condivisione (`share_plus`).

> [!NOTE]
> La risoluzione dipende dalla struttura delle pagine pubbliche di Instagram, che
> **può cambiare**: se un giorno smette di funzionare va aggiornata la logica in
> `instagram_resolver.dart`. Un buon riferimento per ricavare il metodo corrente
> è il traffico di [`yt-dlp`](https://github.com/yt-dlp/yt-dlp)
> (`yt-dlp -v --print-traffic <url>`). Funziona **solo con contenuti pubblici**.

## Requisiti

- Android **7.0+** (API 24)
- Per gli sviluppatori: Flutter, Android SDK, Java 17

## Sviluppo

```bash
flutter pub get
flutter run            # su dispositivo/emulatore Android
flutter analyze
flutter test
```

Generare le icone (da `assets/icon/`):

```bash
python3 tool/gen_icon.py          # rigenera i PNG sorgente
dart run flutter_launcher_icons   # genera i mipmap Android
```

## Build

```bash
# Senza auto-update
flutter build apk --release

# Con auto-update (verso il tuo version.json)
flutter build apk --release --dart-define=UPDATE_URL="https://tuo-host/app/version.json"
```

## Distribuzione / deploy

L'app si installa via **sideload** (APK), non dal Play Store. Puoi pubblicare
l'APK dove preferisci (GitHub Releases, un hosting statico, ecc.). La cartella
[`site/`](site/) contiene una pagina di download pronta e un `.htaccess` (Apache)
che serve l'APK col MIME type corretto.

Procedura completa, firma e auto-update: **[DEPLOY.md](DEPLOY.md)**.
Script build + `version.json` + upload FTP: `./scripts/release.sh --upload`
(configurazione in `.deploy.env`, vedi `.deploy.env.example`).

## Licenza

Progetto a scopo personale/educativo. Aggiungi la licenza che preferisci (es.
[MIT](https://opensource.org/licenses/MIT)) creando un file `LICENSE`.
