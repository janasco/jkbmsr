# ESP8266 NodeMCU Support (UART only, experimental)

`env:esp8266-nodemcu` (`board = nodemcuv2`) targets a classic ESP8266-based
NodeMCU board — a cheaper, UART-only alternative to the ESP32 target, for
packs where BLE isn't needed. Matches jkbmsr-api's `esp8266-uart-lite`
hardware-target entry (`src/services/gatewayHardware.ts`) exactly:
`wifi: true, uart: true, ble: false, ota: false`.

**Experimental, not supported.** There is no ESP8266/NodeMCU hardware in the
environment this port was built in — it compiles cleanly (`pio run -e
esp8266-nodemcu`), but SoftwareSerial reliability under real WiFi load, TLS
handshake behavior on this chip's smaller stack, and the full
provisioning-to-claim flow have not been verified on real hardware. Treat
this the same way jkbmsr-api's own `releaseStatus: "experimental"` already
does — test thoroughly with real hardware and a real BMS before relying on
it.

## Why no BLE

Not a config choice — the ESP8266 has no Bluetooth radio at all. Every BLE
client class and the NimBLE-Arduino dependency are excluded from this
target's build entirely (`platformio.ini`'s `build_src_filter`, plus
`#if JKBMSR_HAS_BLE` gates in `main.cpp`), not just disabled at runtime.
`bmsBleEnabled` in remote config is silently ignored on this target — UART
is always used.

## Why no OTA

The OTA subsystem (`src/ota/OtaClient.cpp`) depends on esp-idf-only mbedtls
signature-verification APIs and the same certificate-bundle mechanism BLE's
absence doesn't affect but OTA's absence does (see below) — it isn't
compiled in at all for this target (`#if JKBMSR_HAS_OTA`). **Firmware
updates on this hardware are USB-reflash only.** A remote "update now"
request is acknowledged and immediately refused
("This gateway hardware does not support OTA updates").

## UART wiring — SoftwareSerial, not a hardware UART

Unlike ESP32 (which has a free, pin-remappable `Serial2` for BMS traffic),
ESP8266 has no hardware UART available for this: `Serial` (UART0) is
already shared with USB/serial-monitor/debug logs/Improv provisioning
(same as ESP32), `Serial1` is TX-only (no usable RX pin), and there's no
GPIO-matrix pin remapping. BMS communication instead runs over
`SoftwareSerial` (bit-banged) on the pins below:

| ESP8266 (NodeMCU) | JK/Daly/JBD BMS UART |
|--------------------|-----------------------|
| GPIO14 / D5 (RX)   | TX                    |
| GPIO12 / D6 (TX)   | RX                    |
| GND                | GND                   |
| —                  | VBAT: never connect   |

Remappable via the same remote-config fields as ESP32
(`bmsUartRxPin`/`bmsUartTxPin`/`bmsUartBaudRate`); these two GPIOs are just
the defaults, matching jkbmsr-api's `esp8266-uart-lite` target.

**Reliability caveat**: SoftwareSerial is bit-banged and shares the single
CPU core with WiFi's own interrupt handling — under real WiFi load (active
transfers, reconnects), frame loss or garbled reads are more likely than on
a hardware UART, especially at higher baud rates (JK-BMS's default is
115200). If reliability turns out to be a real problem in practice, the
concrete escape hatch is lowering `bmsUartBaudRate` (JK/Daly/JBD's UART
protocols don't require running at their default rate — see each vendor's
parser for the accepted range) rather than anything code-level.

## TLS trust

ESP8266's `WiFiClientSecure` is BearSSL-based and has no equivalent to
ESP32's embedded-bundle `setCACertBundle()` API, nor the RAM for a full
Mozilla bundle. This target embeds two specific root CAs instead
(`src/net/SecureClient.cpp`) — see that file's comments for exactly which
two and why two (short version: this target has no OTA, so a single wrong
or rotated root would strand deployed devices with no remote recovery
path). If `api.jkbmsr.com`'s certificate chain ever changes to a CA neither
of those two roots cover, TLS connections from this target will start
failing — check the live chain (`openssl s_client -connect
api.jkbmsr.com:443 -showcerts`) and update the embedded roots, same as any
other cert-rotation response (see `docs/tls-trust-and-cert-rotation.md`).

## First boot / provisioning

Identical flow to ESP32 — Improv Serial (USB) and the SoftAP captive portal
both work unchanged (`ESP8266WebServer`/`DNSServer` swapped in for their
ESP32 equivalents, same behavior). Device ID and claim code generation use
`ESP.random()` in place of esp-idf's `esp_random()`; hardware ID uses
`ESP.getChipId()` (32-bit) in place of `ESP.getEfuseMac()` (48-bit) — both
are per-chip-stable, just narrower, which doesn't matter for their only use
(server-side hardware_id matching).

## Registration

This target reports `targetHardware: "esp8266-uart-lite"` and
`hardwarePlatform: "esp8266"` at device registration
(`src/cloud/DeviceRegistrationClient.cpp`) — jkbmsr-api already validates
and stores both fields against its `gatewayHardwareTargets` catalog
(`src/routes/device.ts`), so no backend changes were needed for this.
