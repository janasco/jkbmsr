# JK BMS Bluetooth Changelog

Customer-facing "what's new" notes, one entry per tagged release
(`vX.Y.Z`, matching `pubspec.yaml`'s `version:` and the git tag the release is
cut from). Written in plain language: what changed, not how it was built. No
implementation detail, no internal tool/repo names.

The same text is passed to `scripts/publish-release.sh`/the Play upload as the
release notes and copied into Google Play Console's "What's new in this
version" field, which has a hard 500-character limit per release — keep each
version's bullets within that, combined.

## v4.17.27+47

- The event log now has its own screen, opened from the side menu: your full history is saved on the phone so you can browse it offline and scroll back through everything the BMS has recorded.
- Only one scanning animation shows while searching for devices.

## v4.17.26+46

- Screens now show a soft placeholder outline while their data loads, instead of a blank spinner — so the layout appears instantly and doesn't jump when the data arrives.

## v4.17.25+45

- New Device information panel: model, hardware and firmware revision, serial number, manufacturing date, power-on count and run time.
- New Event history panel: fetch the battery's built-in event log on demand to see what tripped and when it cleared.
- The scan now animates and can be re-run anytime; the Control PIN shows only while a battery is connected.
- Removed a redundant top-right menu and fixed a cropped app logo.

## v4.17.24+44

- The app is now named JK BMS Bluetooth. Same app, same data — only the name on
  your home screen changed.
- Fixed the Software Update screen being hard to read in light mode.
- Tidied navigation: controls now live in one Controls tab, and App settings
  moved into the drawer.
