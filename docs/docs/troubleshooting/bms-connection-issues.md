# BMS Connection Issues

If no JK-BMS data appears:

1. Confirm the BMS is a JK-BMS.
2. Confirm the JK-BMS is powered on and awake (a sleeping pack does not
   advertise over Bluetooth).
3. Confirm the BMS is within Bluetooth range of the gateway.
4. Check the gateway's BLE state and discovered-address diagnostics in the
   dashboard.
5. If several packs are nearby, set an explicit BMS Bluetooth address so the
   gateway does not connect to the wrong unit.
6. Confirm the ESP32 is not being powered from battery pack voltage.

## The gateway is online but there is no battery data

These are two different states, and the dashboard shows them separately:

- **Gateway offline**: the gateway itself has not checked in. Check its power and
  WiFi.
- **Gateway online, no BMS data**: the gateway is reporting, but the Bluetooth
  link to the pack is down. The device page shows the last error and the RSSI it
  saw.

While the link is down the gateway keeps sending a heartbeat, so the gateway
stays visible and the missing piece is named rather than looking like a dead
device.

From firmware 0.9.12 the recovery path is bounded:

- a dropped link is retried after 30 seconds, then at most every 60 seconds;
- a link that connects but sends no data for 30 seconds is dropped and
  re-established, instead of staying attached and silent.

What to check when this happens repeatedly:

1. **Signal strength.** An RSSI weaker than about -85 dBm is marginal. Move the
   gateway closer, get it out of a metal enclosure, or reorient the antenna.
2. **Power.** A gateway on a weak supply browns out during a WiFi transmit and
   looks like a Bluetooth fault.
3. **One pack at a time.** Two nearby packs with the same name confuse discovery;
   set an explicit BMS Bluetooth address.
