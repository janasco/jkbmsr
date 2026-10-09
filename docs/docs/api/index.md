# API Reference

JKBMSR Cloud exposes a REST API under `/v1`.

The older `/api/v1` prefix remains a permanent alias that serves the same
endpoints (it is not a redirect, so non-GET methods work unchanged). It exists
for already-installed apps and deployed firmware that hardcode it and cannot be
updated; new integrations should use `/v1`.

## Endpoints

- `POST /v1/device/register`
- `POST /v1/device/login`
- `POST /v1/telemetry`
- `GET /v1/device/config`
- `GET /v1/ota/latest`
- `GET /v1/dashboard/devices/:deviceId/telemetry/history`
- `GET /v1/dashboard/devices/:deviceId/ota/history`
- `GET /v1/dashboard/firmware/releases`
