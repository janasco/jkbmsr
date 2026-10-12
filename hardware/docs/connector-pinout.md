# Connector Pinout Notes

The JKBMSR Mini gateway talks to the JK-BMS over **Bluetooth (BLE)** — there
is no wired BMS connection and therefore no BMS connector or pinout to route.

## No BMS Connector

Earlier revisions of this document specified a JST connector wired to the
JK-BMS UART ("GPS") port. That link has been retired: the firmware is
BLE-only, so the board carries no BMS interface. The JK-BMS is paired over
the air; the gateway itself only needs power and a USB-C port for
programming and service.

## Board Interfaces

- USB-C — power, programming, and serial logs.
- Power input — regulated (buck converter or USB-C); never battery pack
  voltage directly.
- Status LEDs and reset/boot buttons.

## Warnings

- Do not connect battery pack voltage to the ESP32.
- Use a properly rated power supply.
- Wrong wiring can permanently damage the ESP32.
