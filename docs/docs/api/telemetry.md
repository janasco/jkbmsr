# Telemetry API

```text
POST /v1/telemetry
```

Uploads JK-BMS telemetry from an authenticated ESP32 gateway.

The raw telemetry payload now also supports persistent OTA runtime event recording when the firmware reports non-idle OTA result fields.
