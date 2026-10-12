# Wiring Safety

Wrong power wiring can damage electronics or create a dangerous condition.

The gateway reaches the JK-BMS over Bluetooth, so there is no BMS signal
wiring to get wrong — the only wiring is power.

## Before Applying Power

- Use a properly rated buck converter or a USB-C supply.
- Verify polarity before applying power.
- Check the supply voltage with a meter.
- Keep battery pack voltage away from ESP32 GPIO pins.

Never assume wire colors are correct.
