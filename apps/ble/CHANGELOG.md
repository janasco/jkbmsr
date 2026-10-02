# JK BMS Bluetooth Changelog

Customer-facing "what's new" notes, one entry per tagged release
(`vX.Y.Z`, matching `pubspec.yaml`'s `version:` and the git tag the release is
cut from). Written in plain language: what changed, not how it was built. No
implementation detail, no internal tool/repo names.

The same text is passed to `scripts/publish-release.sh`/the Play upload as the
release notes and copied into Google Play Console's "What's new in this
version" field, which has a hard 500-character limit per release — keep each
version's bullets within that, combined.

## v4.17.24+44

- The app is now named JK BMS Bluetooth. Same app, same data — only the name on
  your home screen changed.
- Fixed the Software Update screen being hard to read in light mode.
- Tidied navigation: controls now live in one Controls tab, and App settings
  moved into the drawer.
