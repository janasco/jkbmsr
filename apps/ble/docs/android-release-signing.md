# Android Release Signing

Signing is a production security function: whoever holds the upload
keystore can push a legitimately-signed update to every real user of the
app. Treat it accordingly.

This project does not use GitHub Actions. Releases are built and published by
hand, from a machine that holds the signing material.

## Policy

- **Never commit Android signing keys or passwords.** Not in this repository,
  not in a private one. They are supplied locally at build time.
- The upload keystore, its passwords, and the key alias live only on the
  release machine, at the gitignored paths Gradle expects:
  - `android/upload-keystore.jks`
  - `android/key.properties`
- Nothing here is a template for a CI secret store, because there is no CI
  secret store. If you fork this project, generate your own key and keep it
  somewhere you control.
- With no `android/key.properties` present, a release build falls back to
  debug signing and emits a build-time warning. That is fine for a smoke test
  and useless for distribution — a debug-signed APK cannot be published to
  Google Play and will not update an installed app.

## Producing a signed release

```bash
# One-time, on the release machine:
keytool -genkeypair -v \
  -keystore android/upload-keystore.jks \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias upload

# Then write android/key.properties (gitignored). Use android/key.properties.example
# as the shape. Keep this file readable only by the release account.
```

Then, per release:

```bash
scripts/publish-release.sh          # version defaults to pubspec.yaml
scripts/publish-release.sh 4.17.18  # or pass it explicitly
```

The script refuses to run unless the keystore, `key.properties`, and
`scripts/.env.local` (holding `BLE_RELEASE_UPLOAD_SECRET`) are all present, so
a half-configured release machine fails immediately rather than producing an
unsigned artifact.

## Where a release ends up

- **Google Play** — the user-facing distribution channel for BLE. Upload the
  AAB with `scripts/upload_to_play_console.py`; see that script's `--help` for
  authentication.
- **`api.jkbmsr.com/ble/latest.apk`** — the sideload download path. The API
  keeps only the most recent signed APK (R2 key `ble-latest.apk`), so the URL
  always resolves to the current build and is deliberately not versioned.
- **GitHub Releases** — full release history, tagged `vX.Y.Z+BUILD`.

## If the upload key is ever exposed

Whoever holds the upload key can publish updates that reach every installed
copy of the app. If it leaks — committed by accident, exposed in a log, or
in a repository that changes visibility — the only real remedy is to **reset
the upload key in the Play Console** and enrol the replacement. Rotating it
does not affect already-installed apps, because the upload key signs the
upload, not the running app. Do this before changing a repository's
visibility, not after.
