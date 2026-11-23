# Deploy — Reel Saver

Two things to distribute:

1. **the APK** (the Android app)
2. (optional) an **HTML download page** + a **`version.json`** for auto-update,
   hosted on any static host (FTP).

---

## 1. Configuration

Copy the example file and fill in your values:

```bash
cp .deploy.env.example .deploy.env
```

`.deploy.env` is **gitignored** (it does not go into the repo). It contains:

| Variable | Purpose |
|---|---|
| `UPDATE_URL` | URL of the `version.json` used for auto-update. **Empty = auto-update disabled.** |
| `APK_URL` | Public direct URL to the APK (written inside `version.json`). |
| `ARUBA_FTP_HOST` / `ARUBA_FTP_DIR` / `ARUBA_FTP_USER` | Your hosting's FTP. |

The **FTP password** does not go in the file: pass it at runtime (`ARUBA_FTP_PASS=...`).

---

## 2. Building the APK

Requirements: Flutter, Android SDK, Java 17.

Without auto-update:

```bash
flutter build apk --release
```

With auto-update (the app will check your `version.json` on launch):

```bash
flutter build apk --release --dart-define=UPDATE_URL="https://your-host/app/version.json"
```

The APK is at `build/app/outputs/flutter-apk/app-release.apk`.

> **Signing.** The signing config lives in `android/key.properties` (gitignored)
> plus a `*.jks` keystore (gitignored). If the file is missing, the build falls
> back to the *debug key*. To generate a keystore:
> ```bash
> keytool -genkeypair -v -keystore reel-saver-release.jks \
>   -alias reelsaver -keyalg RSA -keysize 2048 -validity 10000
> ```
> then create `android/key.properties` with `storePassword`, `keyPassword`,
> `keyAlias=reelsaver`, `storeFile=../../reel-saver-release.jks`.
> **Always keep the same keystore**, otherwise updates will not install over the
> previous version. Make a **backup** of it (losing it = no more installable
> updates).

---

## 3. Build + version.json + upload in one command

```bash
ARUBA_FTP_PASS="your-password" ./scripts/release.sh --upload
```

The script reads `.deploy.env`, builds (with `UPDATE_URL` if set), copies the APK
into `site/`, regenerates `site/version.json` from `pubspec.yaml` (using
`APK_URL`) and uploads `index.html`, `.htaccess`, `icon.png`, `version.json`,
`reel-saver.apk` to the configured FTP.

Without `--upload` it only builds + writes `version.json` locally (you upload the
`site/` files yourself). Set release notes with `UPDATE_NOTES="• ...\n• ..."`.

> Hosting note: on some providers the web-served folder is a subfolder (e.g.
> `httpdocs/`, `www/`, or a domain folder). Set `ARUBA_FTP_DIR` accordingly.
> `.htaccess` (Apache) makes the APK download with the correct MIME type.

---

## 4. Auto-update — how it works

If built with `UPDATE_URL`, on every launch the app downloads that `version.json`
and compares its `versionCode` with the installed one. If the remote is higher, it
shows a **bottom sheet** that downloads and installs the new APK (this needs the
*"Install unknown apps"* permission, which Android requests on the first update).

`version.json`:

```json
{
  "versionCode": 3,
  "versionName": "1.2.0",
  "apkUrl": "https://your-host/app/reel-saver.apk",
  "notes": "• Change 1\n• Change 2"
}
```

To publish an update: bump the version in `pubspec.yaml` (**always increment the
number after the `+`**, which is the `versionCode`), then run
`./scripts/release.sh --upload`. The `version.json` `versionCode` must never be
higher than the APK actually uploaded, otherwise the bottom sheet keeps reappearing.

---

## 5. Verify

- Open the page from an Android phone and tap *Download*: the APK download must
  start (if the browser opens it instead of downloading, check that `.htaccess`
  was uploaded — it is a hidden file).
- Install and try: Instagram → Share → Reel Saver.
- If something goes wrong, the app has a 🐞 icon (**Export log**) to obtain the
  diagnostic log.
