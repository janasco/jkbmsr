# ESP32 Gateway Setup

The ESP32 gateway connects your JK-BMS to JKBMSR Cloud.

For the first board, follow the full runbook: [First device setup](/getting-started/first-device-setup).

## Before You Start

- Confirm your BMS is a JK-BMS.
- Confirm the ESP32 is powered from USB-C or a safe regulated supply.
- Do not power the ESP32 directly from battery pack voltage.
- Keep wiring disconnected while checking pin labels.
- Use Chrome or Edge for the browser flasher.

## Basic Steps

There are three ways to give the gateway a Wi-Fi network. Use whichever you have
with you. All three are available at the same time while the gateway is waiting
to be set up.

### With the app (phone)

1. Flash firmware at [web.jkbmsr.com/flash](https://web.jkbmsr.com/flash) and keep
   the page open. The console shows a line like `[info] Setup code: 418302`.
2. Leave the gateway powered on and within a few metres of the phone.
3. In the JK BMS Remote app, open **Settings, Tools, Add a gateway** and tap the
   gateway that appears.
4. Type the six digit code, then the Wi-Fi name, password and time zone.
5. The gateway restarts, joins the network and is added to the account you were
   signed in to. There is no separate claim step.

The six digit code is never sent over Bluetooth: it is typed in from the console.
That is what stops someone else nearby from setting the gateway up first.

### With a laptop (USB, Improv)

1. Flash firmware at [web.jkbmsr.com/flash](https://web.jkbmsr.com/flash) in Chrome
   or Edge, signed in.
2. Keep the USB cable connected. The flasher hands the Wi-Fi settings and the
   account link over the same cable.
3. Claim the device at [web.jkbmsr.com/onboard](https://web.jkbmsr.com/onboard)
   with the device ID and claim code if the flasher did not do it for you.

### With a browser only (setup network)

1. Flash the firmware, then join the `JKBMSR-Setup-XXXX` network it creates. The
   password is the claim code printed in the console.
2. Complete the Wi-Fi form on the page that opens.
3. Claim the device at [web.jkbmsr.com/onboard](https://web.jkbmsr.com/onboard).

### After any of them

4. Make sure the JK-BMS is powered and within Bluetooth range of the gateway.
5. Confirm telemetry appears in the dashboard.

## If the app does not find the gateway

- The gateway is powered on and its light is blinking.
- It has **never** been set up. A gateway that already joined a network does not
  advertise, because a running gateway must not be configurable by anyone nearby.
- Bluetooth is on, and the phone is within a few metres.
- The firmware is 0.9.16 or newer. Anything older has no Bluetooth setup.
- If it was flashed with "keep Wi-Fi and identity", it still holds the old network
  and will not appear. A factory reset (hold BOOT for about 10 seconds) clears it.

Claim can succeed before the BMS link is up. Empty SOC/cells until the BMS is
in range and connected is expected.
