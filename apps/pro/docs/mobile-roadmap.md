# Mobile App Roadmap

JK BMS Remote is a Flutter app for Android and iOS. The MVP, device
claim/onboarding, alert history, firmware release visibility, and real push
notifications are implemented; the remaining roadmap is the credentialed
steps in Phase 4 that this environment can't complete on its own (see
`docs/AI_HANDOFF_MOBILE_MVP.md`).

## Phase 1: Planning — complete

- Define screens.
- Define REST API requirements.
- Define notification plan.
- Define Flutter project structure.

## Phase 2: Flutter MVP — complete

- Login.
- Device list.
- Battery dashboard.
- Cell voltage view.
- Alerts.
- Settings.
- OTA status and queued OTA checks.

## Phase 3: Backlog — complete (code)

- Device claim/onboarding against `POST /api/v1/user/devices/claim`.
- Real push notification provider (Firebase Cloud Messaging): permission
  request, token retrieval/refresh, background handler, foreground toast.
- Alert preferences, synced to JKBMSR Cloud per-token
  (`POST /api/v1/user/notifications/register`), not just stored locally.
- Alert history (resolved alerts, paginated) alongside the existing active
  list.
- Firmware release visibility screen, linked from OTA.
- Crash reporting (Firebase Crashlytics), gated the same way as push.

Device-offline notifications are not implemented — nothing server-side
currently evaluates "gateway went offline" and emits an alert/push for it;
that's a backend gap (see the alerts-pipeline gap noted for `jkbmsr-api`), not
a mobile-side one.

## Phase 4: Release Readiness — code ready, blocked on credentials

- App icons and splash screens — needs confirmation of final production
  assets, not just placeholders.
- Store metadata — descriptions, screenshots, content rating: not started.
- Privacy policy and support links — wired into Settings, pointing at
  `jkbmsr.com/privacy` and `jkbmsr.com/contact`.
- Production error reporting — Crashlytics wired, inactive until a real
  Firebase project exists.
- Public APK publishing through `releases/` — `scripts/publish-release.sh`
  already builds, signs (from `android/key.properties` on the release
  machine) and publishes to `mobile/android/`; the signing material just
  isn't populated yet.
- Secure Android signing workflow with no committed signing keys — gradle
  reads `android/key.properties` (gitignored) with a debug-signing fallback;
  the actual upload keystore still needs to be generated and provisioned.
- Android target/compile SDK pinned to **API 36** to meet Google Play's
  target API requirement (`playTargetSdk` in `android/app/build.gradle.kts`).
