# UART Pinout Warnings

UART wiring must be checked carefully.

## Common Mistakes

- Connecting TX to TX and RX to RX.
- Forgetting the shared ground.
- Using the wrong connector orientation.
- Connecting battery pack voltage to a low-voltage communication pin.
- Assuming every JK-BMS cable has the same pinout.

## Warning

Never guess a pinout. Check the JK-BMS documentation, connector labels, and voltage with a meter before connecting the ESP32 gateway.
