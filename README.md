# JK BMS Remote

Independent, open-source monitoring for **JK-BMS** battery systems.

**JK BMS Remote is an independent project. It is not affiliated with, endorsed
by, or sponsored by JK-BMS or its manufacturer.** "JK-BMS" is used only to
describe hardware compatibility. JK-BMS is a trademark of its owner.

JK-BMS is the only battery brand this project supports. Other vendors' protocol
decoders exist in some components for internal testing and reuse; they are not
supported products and are not advertised anywhere in this repository.

No hardware is sold here. You bring your own ESP32 development board and flash
it yourself.

## What is in this repository

| Path | What it is |
| :--- | :--- |
| `apps/ble/` | **JK BMS Bluetooth** — Android app that talks to a JK-BMS over Bluetooth. No account, no gateway, no cloud. |
| `apps/pro/` | **JK BMS Remote** — Android app for gateways running the firmware below. Cloud monitoring and alerts. |
| `firmware/` | ESP32 gateway firmware. Talks to JK-BMS over UART, uploads telemetry, verifies signed OTA updates. |
| `hardware/` | Hardware notes, pinouts, and planning for DIY ESP32 gateway builds. |
| `docs/` | Documentation site source. |
| `support/` | Issue templates and support policy. |
| `releases/` | Signed firmware release artifacts and the OTA index served over CDN. |
| `scripts/` | The manual build, check and deploy scripts. There is no CI; this is the replacement. |

There are exactly two Android apps. The "Supporter" purchase that removes ads
from the BLE app is a Google Play in-app product, **not** a third app.

## Architecture at a glance

```
   JK-BMS pack
       │  Bluetooth (BLE app)          UART (gateway)
       ▼                                 ▼
  ┌────────────────┐                 ┌──────────────┐
  │JK BMS Bluetooth│                 │   firmware   │  ESP32
  │   (no cloud)   │                 │  (ESP32)     │
  └────────────────┘                 └──────┬───────┘
                                         │ HTTPS
                                         ▼
                               api.jkbmsr.com
                               (Cloudflare Worker + D1 + R2)
                                         ▲
                        ┌────────────────┴────────────────┐
                        │                                 │
                 ┌──────┴──────┐                  ┌───────┴──────┐
                 │JK BMS Remote│                  │  web app    │
                 │  (Android)  │                  │ (browser)   │
                 └─────────────┘                  └──────────────┘
```

The BLE app works entirely on-device. Nothing about it requires an account, a
gateway, or an internet connection.

## Quick start

- **Just want to see your battery?** Install the BLE app and pair directly. That
  is the fastest path and it is local-only.
- **Want remote monitoring?** Flash `firmware/` onto your own ESP32 board, then
  use the Pro app. Start with `docs/getting-started/`.
- **Building from source?** See each component's README; `flutter pub get` for
  the apps, `pio` for the firmware.

## Build, check, deploy

**This repository has no CI.** No GitHub Actions, no hosted runners, nothing
runs on a pull request or on a push. GitHub is used for source code storage
only. Whatever is not checked locally is not checked.

Before you open a pull request, run the checks yourself:

```bash
scripts/check-all.sh --run                      # every component
scripts/check-all.sh --run --only firmware      # just the one you touched
```

That covers `flutter analyze && flutter test` for both apps, the native
ASan/UBSan host suites plus the device-profile and hardware-target validators for
the firmware, `npm run docs:build` for the documentation site, and
`python3 scripts/validate_release_index.py` for the release index. Run it with no
arguments to see the plan without executing anything.

Publishing is manual as well. `scripts/stage-docs-at-apex.sh` stages the docs
into the marketing build at `jkbmsr.com/docs/` (the one browsable copy);
`scripts/deploy-docs.sh` keeps the `jkbmsr-docs` Pages project — the
custom-domain origin for the now-retired `docs.jkbmsr.com`, which 301s to the
apex — and `scripts/deploy-releases.sh` builds and publishes `cdn.jkbmsr.com`;
with no arguments they only print what they would do. The operator procedure,
the host map, and the traps that have bitten this project are in
[DEPLOY.md](DEPLOY.md).

## Support scope

- JK-BMS only, over Bluetooth (BLE app) or wired UART (gateway).
- No other BMS vendor is supported.
- Firmware targets ESP32 and ESP8266. See `firmware/platformio.ini` and
  `releases/firmware/hardware-targets.json` for the list of published targets and
  which ones have Bluetooth.

## Before you open an issue

Read `support/README.md`. It explains how discussions are organised and what
makes a useful report — exact model, connection type, cell count, firmware
version, what you expected and what happened.

## Contributing

See `CONTRIBUTING.md`. Two rules matter most:

1. **Never guess a protocol.** Any change to a frame format, checksum, register
   address or byte offset must be verified against a real reference
   implementation or a captured frame from real hardware. Guessed bytes on a
   battery-management protocol are a safety problem, not a bug.
2. **Never commit secrets.** Signing keys, Firebase config, `.env` files and
   credentials are excluded from this repository by design and are supplied
   locally. See `CONTRIBUTING.md` for the specifics.

And the rule that follows from having no CI: **run the checks yourself before
you open a pull request** (`scripts/check-all.sh --run`). Nothing else will.

## Licence

MIT — see `LICENSE`.

Some components re-derive protocol details from community-maintained
implementations under Apache-2.0 and MIT; those attributions are recorded in
`firmware/docs/third-party-attribution.md`.
