# Telemetry Timing Bench Test

Use this runbook to verify two related firmware changes on a real ESP32
gateway before cutting a `firmware-vX` OTA release. Both were built and
compile-verified (`pio run -e dev`) in an environment with no hardware
access, so neither has been proven on a real board yet.

1. **Wall-clock-aligned telemetry sends** — `telemetryDue()` in
   `src/main.cpp` now fires once per interval-aligned UTC epoch second
   (every gateway on a 1-minute interval reports at `:00` of every minute,
   etc.) instead of a boot-relative `millis()` timer.
2. **Free tier interval clamp fix** — `RemoteConfigClient.cpp` and
   `DeviceRegistrationClient.cpp` now accept up to `3600` seconds
   (matching the Free tier's real 1-hour interval) instead of clamping to
   `1800`.

## When To Use It

Run this after:

- either of the two source changes above, if not yet bench-tested
- before tagging a `firmware-vX` OTA release that includes them
- after any future change to `telemetryDue()`, `RemoteConfigClient.cpp`,
  or `DeviceRegistrationClient.cpp`

## Prerequisites

- ESP32 gateway connected over USB
- serial port visible as `/dev/ttyUSB*` or `/dev/ttyACM*`
- PlatformIO installed (`.platformio-core/penv/bin/pio` if using the
  repo-local install)
- network access to `https://api.jkbmsr.com`
- a way to check the current wall-clock time against the serial log (a
  phone clock is fine — this only needs to be accurate to the second)

## Part 1: Wall-Clock Alignment

1. Flash the current build to the bench board and open the serial monitor:

   ```bash
   pio run -e dev -t upload --upload-port /dev/ttyUSB0
   pio device monitor -b 115200
   ```

2. Confirm `"System clock synchronized"` appears in the log shortly after
   boot (NTP sync succeeded — `telemetryDue()` falls back to the old
   boot-relative timer until this happens, so alignment can't be checked
   before it).
3. Note the device's configured interval (`telemetryIntervalSeconds` from
   its last `GET /v1/device/config` response, visible in the log).
4. Record the wall-clock time of the next 3-4 telemetry sends (look for
   the telemetry POST log line). Confirm each one lands on a clean
   boundary for that interval — e.g. at a 60s interval, every send should
   be at `:00` seconds of its minute; at 3600s, every send at `:00:00` of
   its hour.
5. **Reboot the board mid-interval** (power cycle or reset), then confirm
   the *next* send after reboot still lands on the same kind of boundary
   as before — not reset to a new offset measured from the reboot time.
6. If a second bench board is available, flash it with the same interval
   and confirm both boards' sends land on the *same* boundary instants
   (this is the actual point of the change — telemetry from different
   gateways lining up on a shared clock).

**Proves:** sends align to UTC clock boundaries, survive a reboot without
losing alignment, and (with two boards) genuinely synchronize across
devices.

**Does not prove:** behavior across an NTP resync failure/retry mid-run,
or behavior with a very short (10s) interval under CPU load from BLE —
worth a quick look if either is a concern, not covered by the steps above.

## Part 2: Free Tier Interval Clamp

1. On a test account, set the device's Cloud Service plan to Free (or use
   the admin console / `jkbmsr-api` directly to set the device's
   `device_configs.telemetry_interval_seconds` to `3600`).
2. Trigger a remote config refresh (either wait for the periodic fetch —
   `kRemoteConfigIntervalMs`, currently 60s — or power-cycle the board so
   it re-authenticates via `DeviceRegistrationClient`).
3. Check the serial log's parsed config: confirm the interval the board
   actually applied is `3600` seconds, not clamped down to `1800`.
4. Let it run for at least two send cycles and confirm real-world cadence
   is roughly hourly, not every 30 minutes. Easiest to see end-to-end via
   the device's row in `jkbmsr.com/dashboard` or the `jkbmsr.com/data` tab
   (`lastSeen` / the telemetry table's row spacing).

**Proves:** a Free tier gateway now actually reports at its intended
1-hour cadence instead of silently doubling its upload rate.

## Current Limitation

Neither part of this bench test has been run yet — this document was
written from a sandboxed environment with no physical hardware access
(no `/dev/ttyUSB*`/`/dev/ttyACM*` visible, no USB tooling installed).
Both firmware changes are merged to `main` and CI-green, but unverified
on real hardware. Do not tag a `firmware-vX` release from these changes
until this runbook has actually been run once.
