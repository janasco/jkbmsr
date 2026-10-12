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
