<div align="center">
  <img src="assets/icon/icon.png" width="96" alt="Reel Saver" />
  <h1>Reel Saver</h1>
  <p>Android app (Flutter) to download <b>public</b> Instagram reels/posts,
  save them to the gallery and re-share them on Telegram / WhatsApp.</p>
</div>

---

> [!WARNING]
> **Personal and educational use.** Instagram offers no official download API and
> this project is not affiliated with or endorsed by Instagram/Meta. Download
> **only** public content and **only** if you have the right to save it,
> respecting the authors' copyright and the
> [Instagram Terms](https://help.instagram.com/581066165581870). Downloading
> other people's content may violate those terms: responsibility for any use lies
> with whoever uses the app.

## Features

- Appears in Instagram's **Share** menu (share intent `text/*`).
- Receives the reel/post URL (or you paste it manually).
- **Downloads the video** as a single `.mp4` file (H.264 + audio), ready to share.
- **Saves it to the gallery** (album *Reel Saver*).
- **Re-shares it** to Telegram, WhatsApp, etc. with one tap.
- **Optional auto-update**: if configured with an *update URL*, on launch it
  checks for a newer version and offers it in a bottom sheet.
- **Exportable diagnostic log** (🐞 icon) to understand any errors.

## How it works (architecture)

Everything runs **client-side, with no backend**:

- [`lib/services/instagram_resolver.dart`](lib/services/instagram_resolver.dart)
  — turns an Instagram URL into the direct video link. It establishes a session
  (cookies) and fetches the `/p/{shortcode}/` page with browser-like headers
  (`Sec-Fetch-Mode: navigate`), then extracts `video_versions` from the
  `data-sjs` blocks. Fallbacks: the GraphQL endpoint and `api/v1/media/{id}/info/`.
- [`lib/services/download_service.dart`](lib/services/download_service.dart) —
  download with progress (`dio`) + save to gallery (`gal`).
- [`lib/services/update_service.dart`](lib/services/update_service.dart) —
  auto-update via a remote `version.json` (active only if `UPDATE_URL` is set at
  build time).
- [`lib/main.dart`](lib/main.dart) — UI, share receiving
  (`receive_sharing_intent`), re-sharing (`share_plus`).

> [!NOTE]
> Resolution depends on the structure of Instagram's public pages, which **can
> change**: if it stops working one day, the logic in `instagram_resolver.dart`
> must be updated. A good reference to derive the current method is the traffic of
> [`yt-dlp`](https://github.com/yt-dlp/yt-dlp)
> (`yt-dlp -v --print-traffic <url>`). Works **with public content only**.

## Requirements

- Android **7.0+** (API 24)
- For developers: Flutter, Android SDK, Java 17

## Development

```bash
flutter pub get
flutter run            # on an Android device/emulator
flutter analyze
flutter test
```

Regenerate the icons (from `assets/icon/`):

```bash
python3 tool/gen_icon.py          # regenerate the source PNGs
dart run flutter_launcher_icons   # generate the Android mipmaps
```

## Build

```bash
# Without auto-update
flutter build apk --release

# With auto-update (pointing at your version.json)
flutter build apk --release --dart-define=UPDATE_URL="https://your-host/app/version.json"
```

## Distribution / deploy

The app is installed via **sideload** (APK), not through the Play Store. You can
publish the APK wherever you like (GitHub Releases, a static host, etc.). The
[`site/`](site/) folder contains a ready-made download page and an `.htaccess`
(Apache) that serves the APK with the correct MIME type.

Full procedure, signing and auto-update: **[DEPLOY.md](DEPLOY.md)**.
Build + `version.json` + FTP upload script: `./scripts/release.sh --upload`
(configuration in `.deploy.env`, see `.deploy.env.example`).

## License

Personal/educational project. Add the license of your choice (e.g.
[MIT](https://opensource.org/licenses/MIT)) by creating a `LICENSE` file.
