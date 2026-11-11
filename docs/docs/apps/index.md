# Apps

JK BMS Remote has three mobile apps plus the web dashboard. They are not one
product with three front ends:

- **The web dashboard and JK BMS Remote (Pro)** share one account and one gateway
  fleet, so a gateway you claim in either shows up in the other.
- **JK BMS Bluetooth** is standalone. No gateway, no cloud, no account.
- **JK BMS Contributor** is anonymous by design. No account, and off until you
  turn it on.

## Web dashboard

The product app for managing gateways, viewing live telemetry and history,
configuring alerts, and flashing/onboarding new gateways.

- URL: [web.jkbmsr.com](https://web.jkbmsr.com)
- Best for: setup, configuration, history, and anything with a keyboard.

## JK BMS Remote (Android)

The companion app for the **ESP32 gateway** product. It reads the cloud, so it
works from anywhere (same data as the web dashboard) and adds:

- Live dashboard with an animated energy-flow strip and SOC ring
- Per-gateway alert thresholds and notification preferences
- Alert list grouped by gateway, with one-tap clear
- Firmware (OTA) status and release history
- Biometric unlock after a session timeout
- Google Play: [JK BMS Remote](https://play.google.com/store/apps/details?id=com.jkbmsr.pro)

## JK BMS Bluetooth (Android)

A standalone, direct-Bluetooth monitoring app: **no gateway, no cloud, no
account required**. It connects straight to the BMS's Bluetooth module and
is built and tested against JK-BMS.

- Best for: on-site checks with no gateway, cloud, or account in the way.
- Includes per-cell monitoring with a balance trend, control switches, and
  parameter editing on the JK-BMS protocols this app implements.
- Google Play: [JK BMS Bluetooth](https://play.google.com/store/apps/details?id=com.jkbmsr.ble)

## JK BMS Contributor (Android)

A separate, optional app for donating anonymous captures of a real JK-BMS, so the
decoder can be tested against hardware nobody here owns. It has **no account, no
sign-in and no dashboard**, and it is off by default: nothing is captured or sent
until you switch it on and press Submit.

- Reads a JK-BMS over Bluetooth and never writes to it.
- Captures short sessions of raw frames once and then stays out of the way.
- The battery serial is withheld by default; if you opt in, only a one-way hash is
  stored. The Bluetooth address is reduced to the vendor prefix.
- What has been donated, and what is deliberately never kept, is published at
  [jkbmsr.com/contributor/transparency](https://jkbmsr.com/contributor/transparency/).
- Google Play: [JK BMS Contributor](https://play.google.com/store/apps/details?id=com.jkbmsr.contributor)

## Getting the apps

- Android, all three apps: [jkbmsr.com/download](https://jkbmsr.com/download)
- Google Play: [JK BMS Remote](https://play.google.com/store/apps/details?id=com.jkbmsr.pro) · [JK BMS Bluetooth](https://play.google.com/store/apps/details?id=com.jkbmsr.ble) · [JK BMS Contributor](https://play.google.com/store/apps/details?id=com.jkbmsr.contributor)
- Web dashboard: [web.jkbmsr.com](https://web.jkbmsr.com)
