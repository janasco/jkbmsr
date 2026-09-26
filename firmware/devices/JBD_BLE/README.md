# JBD-BMS — BLE

Compatibility profile for JBD (Jiabaida) BMS units over BLE. The frame
format is **byte-identical** to [`JBD_UART`](../JBD_UART/)'s protocol
(`0xDD`...`0x77` framing, same command bytes) — confirmed by reading
`syssi/esphome-jbd-bms`'s dedicated `jbd_bms_ble` component alongside its
UART-only `jbd_bms` component. Because of that, this profile shares the
**same decoder** as the UART profile (`src/bms/JbdBmsParser.cpp`) — only
the transport (`src/bms/JbdBmsBleClient.*`) is new.

- Hardware revisions: units using the default `0xFF00` service UUID (a
  minority of rebrand SKUs configure different UUIDs upstream; not handled
  here)
- Protocol family: `JBD_UART` (same protocol id as the UART profile,
  intentionally — see above)
- Connection: BLE, service `0xFF00`, notify characteristic `0xFF01`, write
  characteristic `0xFF02`

Ported from `syssi/esphome-jbd-bms`'s `jbd_bms_ble.cpp` (Apache-2.0,
transport only — decoding logic was already ported from `jbd_bms.cpp` for
the UART profile) — see `docs/third-party-attribution.md`.

**Important**: these are the same UUIDs [`SEPLOS_BLE`](../SEPLOS_BLE/)
uses. Address-less auto-discovery can pick the wrong unit if both a JBD and
a Seplos device are advertising nearby simultaneously. Configure an
explicit `bmsBleAddress` when this might be a concern — JBD has no
reliable advertised-name prefix the way JK (`JK`) or Daly (`DL-`) do. As a
second line of defense, `JbdBmsBleClient::loop()` disconnects and retries
against the next-strongest candidate if a connection produces no valid
frame within `kFrameValidationTimeoutMs` (20s) — this also helps recover
from the password-protected-unit case below, which otherwise looks
identical to a wrong-vendor lock (connected, no telemetry, ever).

## Scope of this first pass

Explicitly not implemented: the password-authentication sub-protocol
(`0xFF 0xAA`...`0x77` framed) that a small minority of JBD BLE units
require before they'll answer telemetry requests (one model in upstream's
own supported-devices list is flagged as needing `password: "123456"`).
Units that need this will connect, then get disconnected and retried by
the frame-validation timeout above once it elapses, since they'll never
answer a telemetry request without it.

## Status: synthetic-fixture-only

No new decoder tests exist for this profile — it reuses
`JbdBmsParser::parseFrame()`, already covered by
`test/test_jbd_bms_parser/`. See `fixtures/README.md`.

## Hardware regression fixture

After a successful physical-device session, save a sanitized BLE
notification capture in `fixtures/` and add it to
`test/test_jbd_bms_parser/` (the shared decoder test), then update this
profile's `status`. Never commit Wi-Fi credentials, device secrets, or
cloud tokens.
