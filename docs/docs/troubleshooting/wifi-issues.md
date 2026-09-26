# WiFi Issues

Check that the SSID and password are correct and that the ESP32 gateway is within range of a **2.4 GHz** access point.

## Browser Improv

- Use Chrome or Edge on the same USB cable used for flash.
- If Improv never appears, power-cycle the board and reopen [cdn.jkbmsr.com/flash](https://cdn.jkbmsr.com/flash).
- Captive portals / enterprise Wi‑Fi that block unknown HTTPS hosts will prevent cloud register after join.

## SoftAP fallback

- Join `JKBMSR-Setup-XXXX` (password = claim code).
- Complete captive-portal Wi‑Fi setup, then return to the customer network.
- Claim still requires the gateway to reach `api.jkbmsr.com` after it joins.

## Serial checks

Power cycle the gateway and watch USB serial at 115200 for SoftAP name, join success, and register errors.

See [First device setup](/getting-started/first-device-setup) and [Claim and onboard issues](/troubleshooting/claim-and-onboard-issues).
