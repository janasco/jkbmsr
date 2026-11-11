# Release Notes

Firmware is installed from the logged-in browser flasher at
<https://web.jkbmsr.com/flash>. The current version per target is resolved from the
authenticated API, not a static public file.

## 2026-11-11 · v0.9.14

- The gateway now reports **once, immediately, after it connects to the BMS**,
  instead of waiting for the next interval boundary. On the free tier that
  boundary is an hour away, so a freshly booted gateway used to be invisible on
  the dashboard for up to an hour even though it was working.
- The regular hourly (or faster, with Cloud Service) cadence is unchanged. One
  extra report per connection, throttled so a failed upload cannot retry in a
  tight loop.

## 2026-11-11 · v0.9.13

- **New target: `esp32-s3-16mb-quad`** for 16 MB ESP32-S3 modules with **quad**
  PSRAM. Until now the only 16 MB image was built for octal PSRAM, and a quad
  module running it resets in the bootloader before printing anything. If your
  board showed no log output at all after flashing, this is the image for it.
- No change to the other seven targets beyond the version.

## 2026-11-10 · v0.9.12

- Faster recovery when the pack link drops. The reconnect delay now caps at
  **60 seconds** instead of five minutes, and it resets as soon as a valid frame
  arrives, so a flaky link no longer escalates to the slowest retry and stays there.
- A link that is connected but sends nothing for 30 seconds is now **dropped and
  re-established**, instead of holding a half-open session while the gateway
  reports "BMS link down". The stale-stream request still runs first.
- If your dashboard showed long gaps while the gateway stayed online, this is the
  firmware for it.

## 2026-11-10 · v0.9.11

- The serial log now carries a timestamp on every line, rendered in the gateway's
  **own time zone** (`[info] 2026-11-10 15:04:05 …`). Before the first clock sync
  the lines show seconds since boot (`[+12s]`) rather than a made-up date.
- Set the zone in the web app under **Settings → General → Gateway time zone**.
  It applies on the next check-in, with no reboot, and only changes how times are
  *displayed*: stored telemetry is always UTC.

## 2026-11-09 · v0.9.10

- Frame reassembly now works over the byte stream rather than per notification,
  so gateways whose frames are preceded by an echoed read command or `AT`
  commands no longer discard every frame as a header/checksum mismatch.
- Fixes telemetry that stopped after a successful connection on some hardware.

## 2026-10-15 · v0.9.9

- Retries that make the pack **beep** are now backed off: the stalled-stream
  request and the reconnect attempt widen their delay instead of repeating on a
  fixed cadence, so a dead link stops beeping every few seconds.

## 2026-10-14 · v0.9.8

- JK-BMS only: the other vendor decoders are no longer part of the firmware
  build.
- Cell *presence* is reported explicitly, so an unpopulated cell slot is no
  longer shown as a cell reading 0 V.

## 2026-10-13 · v0.9.7

- Production release across all supported gateway hardware.
- Current version per `releases/ota/*-latest.json`.

## 2026-10-13 · v0.9.6

- Production release across all supported gateway hardware.

## 2026-10-13 · v0.9.5

- N16R8 target on arduino-esp32 3.2.0 / IDF 5.4.1.

## 2026-10-13 · v0.9.4

- N16R8 Octal-PSRAM target.

## 2026-10-13 · v0.9.3

- BLE-only BMS link.

## 2026-10-09 · v0.9.2

- Release script isolates the pioarduino (C6) core dir and bootstraps pip.

No tagged firmware releases exist between `v0.1.2` (2026-07-05) and `v0.9.2`
in this repository.

For release-by-release details, see the release index at
<https://cdn.jkbmsr.com/> and the GitHub releases on
<https://github.com/janasco/jkbmsr/releases>.
