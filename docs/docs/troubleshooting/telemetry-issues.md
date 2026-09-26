# Telemetry Issues

If telemetry does not appear in JKBMSR Cloud:

1. Confirm Wi‑Fi is connected and the device shows **online** in the dashboard.
2. Confirm the device was **claimed** (not only flashed).
3. Confirm JK-BMS UART is wired and the BMS is powered/awake.
4. Empty SOC / zero voltage with an online device usually means “claimed, waiting for BMS frames” — not a cloud outage.
5. Check device settings for RX/TX pins and baud rate.
6. Confirm the gateway can reach `https://api.jkbmsr.com` (outbound HTTPS).

See also [Claim and onboard issues](/troubleshooting/claim-and-onboard-issues) and [BMS connection issues](/troubleshooting/bms-connection-issues).
