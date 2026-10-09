# JK BMS Remote Changelog

Real, per-release "what's new" notes — one entry per tagged release
(`vX.Y.Z`, matching `pubspec.yaml`'s `version:` and the git tag the
release is cut from), in customer-facing plain
language: what changed, not how it was built. No implementation detail,
no internal tool/repo names, no dates.

**Every tagged release must have an entry here** — `release.yml` reads
the section matching the tag being released and fails the build if it's
missing, so this can't silently go stale. Bullets under a version are
also written to a `whatsnew`-style text file attached to the GitHub
Release, meant to be copied directly into Google Play Console's "What's
new in this version" field (which has a hard 500-character limit per
release — keep each version's bullets within that, combined).

## v1.3.43

- Acknowledge an offline alert or mute a gateway's offline alerts right from its dashboard, so you stop getting emails and push for an outage you already know about.

## v1.3.42

- Set a gateway's Wi-Fi remotely from Settings, Wi-Fi — no need to be on site. The gateway picks it up on its next check-in, and we'll alert you if it can't reach the network.
- Added Check for updates to the About menu.

## v1.3.41

- The dashboard now shows a live countdown to the next expected update ("Next update in …"), based on your gateway's check-in interval.
- Comparison and other loading views now use placeholder outlines instead of a spinner.

## v1.3.40

- Cloud Service history CSV exports now cover the whole range you pick — a 30/90/365-day export includes older hourly data instead of only the last week.
- Added a Protection Warnings switch: cell-imbalance and over-current alerts are now on by default but can be turned off on their own, without muting critical battery alarms.

## v1.3.39

- Notifications now work reliably. You'll be asked to allow them when you sign in, and low-temperature, cell-imbalance and high-current alerts now notify you like the others.
- Fixed Share CSV in Cloud Service history — it now exports a real CSV file instead of failing.

## v1.3.38

- Added support for the newest Android devices and 16 KB memory pages, so the app runs correctly on them and future updates keep arriving through Google Play.

## v1.3.37

- If you installed JK BMS Remote from Google Play, updates now come through Play itself, right inside the app.
- Copies installed directly from our website keep updating in the app as before.

## v1.3.36

- The Alert summary counts (Active Alarms / Critical / Warnings) now have clear separation, so the numbers no longer sit flush against their labels.

## v1.3.35

- Push notifications now use a refreshed cloud service, so alerts reach your phone reliably again.

## v1.3.34

- The Cloud Service screen now explains that subscriptions are managed on the website, without opening a browser.

## v1.3.33

- Push notifications are now enabled, so gateway alerts can reach your phone even when the app is closed.

## v1.3.32

- The app is now named JK BMS Remote, matching the rest of the product. Same app, same data — only the name on your home screen changed.

## v1.3.31

- If a gateway is online but has lost its link to the battery, the app now explains why the readings are empty instead of leaving you guessing.

## v1.3.30

- Updated the app's logo to match the current JK BMS Remote branding, with versions that adapt automatically to light and dark themes.

## v1.3.21

- Larger tap target on the inline "Acknowledge" button; animations now respect your device's reduced-motion setting.

## v1.3.20

- No label is smaller than 11px anymore — dashboard templates, metrics, and comparison screens are easier to read.

## v1.3.19

- Small dashboard metric labels are slightly larger for legibility.

## v1.3.18

- Clearer bottom-navigation icons (Alerts no longer uses a heart).
- Correct screen titles for Gateways and Cloud History (the Dashboard tab no longer lights up for them).
- Tidied the command palette (removed a no-op "Sign Out" entry; renamed misleading items).

## v1.3.17

- The firmware action now reads "Check for update" (it asks the gateway to check and install) instead of implying an immediate flash.

## v1.3.16

- Settings: fixed the cramped "Recent Sign-ins" header on first visit, and removed the redundant "Setup" heading.

## v1.3.15

- New bottom navigation: the active tab is shown as a filled circular badge on a cleaner pill bar.

## v1.3.14

- The sign-in screen now prompts for your fingerprint/face automatically when Biometric Unlock is enabled, so an idle-timeout sign-out doesn't require typing a password.

## v1.3.13

- Removed the "Sign in with biometrics" button from the sign-in screen. Biometrics still prompts automatically when your session times out.

## v1.3.12

- Biometric sign-in now reports the actual reason when it fails (instead of a generic message).

## v1.3.11

- Fixed biometric sign-in on the login screen — signing out no longer discards your biometric unlock token.
- Added an "update available" prompt when a newer version is published.

## v1.3.10

- Biometric unlock now uses a revocable device token instead of storing your password, and you can enable it with either your account password or an emailed code.

## v1.3.9

- Sign in with biometrics: a "Sign in with biometrics" button now appears on the login screen when Biometric Unlock is enabled.

## v1.3.8

- Alerts: select multiple alarms and resolve them together.

## v1.3.7

- Alerts are grouped by gateway, with a per-gateway "Clear" action to resolve all of that gateway's alarms in one tap.

## v1.3.6

- Alerts: "Clear all alarms" resolves every open alarm across your gateways in one tap.
- Settings → Account: "Clear history" empties the sign-in list (your current session stays active).
- Gateway list search (filter by name or ID).
- Fixed biometric unlock sometimes prompting for your device PIN instead of using your fingerprint or face.

## v1.3.5

- Per-gateway alert thresholds are now also available under Settings → Notifications (alongside the alert-type toggles), so notification setup for each gateway is in one place.
- The gateway list now has a search field (filter by name or ID) — handy for larger fleets.
- Fixed biometric unlock sometimes prompting for your device PIN instead of using your fingerprint or face.

## v1.3.4

- The dashboard energy-flow animation now points the right way when the battery is discharging (pack → home).
- Moved per-cell voltages and the detailed telemetry table off the dashboard — they live on the Cells tab.

## v1.3.3

- New Battery & BMS info panel: pack flow, capacity, cycles, state of health, cell delta, and balancing in one place.

## v1.3.2

- Sharpened the app icon — it could look blurry or pixelated on some devices.
- Crisp launcher artwork on every screen density, from phones to high-DPI displays.

## v1.3.1

- New cloud-and-battery app icon, matching the JKBMSR platform branding.
- Launcher icons and artwork refreshed across all screen sizes.

## v1.3.0

- An Energy Flow dashboard template shows live power and current trends behind each gateway.
- First-time installs are guided through a step-by-step onboarding tour.
- Optional fingerprint or face unlock gets you back in quickly after a session timeout.
- Alerts can be acknowledged directly from the app, syncing with your gateway.
- Compare battery gateways side-by-side on one detailed screen.
- Group gateways into named sets (House, Workshop, RV) for faster filtering.

## v1.2.29

- Your gateway list now shows a subtle live trend behind each card, echoing its recent power and current.

## v1.2.28

- Error messages (like a failed sign-in or a lost connection) now show plain, helpful text instead of raw technical details.
- Removed the telemetry upload interval option from gateway settings — your Cloud Service plan now sets this automatically.

## v1.2.27

- Account deletion now signs you out everywhere immediately and gives you a 30-day window before anything is permanently deleted, instead of deleting right away with no way back.

## v1.2.26

- Added a refund policy link next to the gateway license purchase button.

## v1.2.25

- Fixed the telemetry Upload Interval setting sometimes showing a value faster than your Cloud Service plan allows, with no indication it hadn't actually been saved.

## v1.2.24

- The dashboard layout you pick on mobile no longer changes what you see on the web dashboard, and vice versa — each app now remembers its own choice.

## v1.2.23

- The gateway telemetry upload interval in Settings now only offers speeds your Cloud Service plan actually allows, instead of letting you pick one that would just fail to save.

## v1.2.22

- Fixed all 8 gateway dashboard layouts breaking (overflowing) on smaller phone screens.
- Every layout's detail rows now show an icon next to each value and are grouped more clearly.

## v1.2.21

- Added 5 more gateway dashboard layouts to Settings > Dashboard & Display: Status Pills, Terminal Readout, Severity Gauge, Mosaic Grid, and At-a-Glance Strip — 8 layouts to choose from in total now.

## v1.2.20

- Added alternate gateway dashboard layouts — pick Classic Readout, Gauge & Sparkline, or Icon Tiles from Settings > Dashboard & Display, alongside the original Default layout.

## v1.2.19

- Removed the non-functional "Layout Template" dashboard picker from Settings — it didn't change anything and was confusing.
- The "Battery Charging Animations" toggle in Settings now actually works.

## v1.2.18

- Fixed the gateway dashboard sometimes showing 0% charge, 0V, and N/A readings right after a gateway reconnects, even while it's marked Online — it now shows a clear "waiting for telemetry" message until real data arrives instead of misleading zeros.

## v1.2.17

- Settings is now a simple grouped list, and Logout is available with one tap right from the main Settings screen.
- Added Delete Account to Account settings, so you can permanently delete your account and its data yourself.
- My Gateways now shows an at-a-glance summary: online/offline gateways, active alerts, recent alerts, and an alert breakdown chart.
- Fixed Google sign-in always skipping the account picker and silently reusing the last account.

## v1.2.16

- Settings is now organized into an icon grid by category, so you can jump straight to what you need instead of scrolling through one long list.
- Added a "Clear expired" button to Recent Sign-ins to remove old sign-in records you no longer need.

## v1.2.15

- Added a Cloud Service history screen with 7/30/90/365-day trend charts and CSV export, available offline from cached data.
- You'll now be signed out automatically with a notice if your session expires, instead of the app silently freezing on stale data.
- The app now refuses to run inside a cloned/dual-app install to prevent session conflicts.

## v1.2.14

- Added a Recent Sign-ins list and a Licenses screen to Account settings.

## v1.2.13

- Added Bluetooth connection history to the battery dashboard.
- Dashboard and cell voltage screens now stay live instead of going stale after sitting in the background for a while.
- Settings now save section by section instead of one long form, and the Low Power Mode switch works again.

## v1.2.12

- Maintenance release. No user-facing changes.

## v1.2.11

- Behind-the-scenes release-process improvements. No user-facing changes.

## v1.2.10

- Added one-time-code (OTP) verification to the mobile sign-in screen.

## v1.2.9

- Fixed charging/discharging status sometimes showing incorrectly on the battery dashboard.

## v1.2.8

- Device screens now show a short GW-XXXXXXXX code instead of the full internal device ID.
- Privacy, Terms, and Support links now open without leaving the app.
- Added a 15-minute idle sign-out for better account security.

## v1.2.7

- Added Google Sign-In.
- New alert threshold controls: cell voltage imbalance, minimum temperature, maximum current.
- Cell voltage bars now animate individually for a more dynamic look.
- Moved OTA firmware updates into Settings and improved the Alerts tab.
- Added a Terms of Service link alongside Privacy Policy.

## v1.2.1

- Fixed a crash in the navigation sidebar.

## v1.2.0

- Added gateway sharing — grant or revoke view-only access to another account.
- See individual cell voltages right on the main dashboard.
- Manage gateway WiFi remotely: scan and change networks from the app.
- See activation/trial status and unlock gateways from Settings.
- Redesigned the battery metrics card and alert-threshold configuration.
- The selected gateway now stays selected when switching tabs.

## v1.1.0

- Scan your gateway's claim QR code instead of typing it in.
- New app icon.
- Fixed long device IDs overflowing the screen.

## v1.0.0

- Initial release: monitor your battery gateways, view live telemetry, manage alerts, and claim new devices.
