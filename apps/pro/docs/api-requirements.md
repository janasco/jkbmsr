# Mobile API Requirements

The mobile app will use the JKBMSR Cloud REST API over HTTPS.

## Required Capabilities

- Customer login.
- List devices owned by the user.
- Fetch latest telemetry for a device.
- Fetch cell voltage data.
- Fetch active and historical alerts.
- Fetch and update device settings.
- Fetch OTA status.

## Device API Alignment

The mobile app should not talk directly to ESP32 devices. It should only use JKBMSR Cloud APIs.

## Firmware Release Visibility

The mobile app should eventually consume the same release visibility data used by the web dashboard, including:

- available firmware versions
- target hardware
- release date
- verification state
