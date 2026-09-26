# JK-BMS Wiring

The ESP32 gateway communicates with JK-BMS over UART.

## Safety Warnings

- Turn off power before changing wiring.
- Do not connect battery pack voltage to the ESP32.
- Confirm the JK-BMS communication port voltage before connecting it.
- Wrong wiring can permanently damage the ESP32, JK-BMS, or battery system.

## UART Wiring

- ESP32 TX connects to JK-BMS RX.
- ESP32 RX connects to JK-BMS TX.
- ESP32 GND connects to JK-BMS communication ground.

TX and RX are crossed because one device transmits while the other receives.
