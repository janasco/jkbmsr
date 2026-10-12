# JK-BMS Connection

The ESP32 gateway communicates with the JK-BMS over **Bluetooth (BLE)**. No
communication cable is required between the gateway and the battery.

## Before You Start

- Confirm your BMS is a JK-BMS.
- The JK-BMS must be powered and awake so it advertises over Bluetooth.
- The gateway needs a stable power supply (USB-C or a regulated supply).

## How the Link Works

- The gateway scans for the JK-BMS Bluetooth advertisement (service UUID
  `0xFFE0`) and connects automatically.
- Leaving the BMS address unset uses auto-discovery of the strongest nearby
  unit; set an explicit BMS Bluetooth address in device settings to pin one
  pack.
- The connection is read-only: the gateway only reads telemetry and never
  writes settings to the battery.

## Enabling It

1. Power the gateway and confirm it is online in the dashboard.
2. Make sure the JK-BMS is powered and in Bluetooth range of the gateway.
3. Confirm telemetry appears in the dashboard. Link state, address, and RSSI
   are visible in device diagnostics.

## Safety Warnings

- Do not open the battery pack to add wiring; the link is wireless.
- Do not connect battery pack voltage to the ESP32.
- Keep the gateway physically clear of high-current battery wiring.
