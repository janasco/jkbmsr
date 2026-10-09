# API Reference

JKBMSR Cloud exposes a REST API under `/v1`.

`/v1` is the only prefix. The legacy `/api/v1` alias was retired and is no
longer mounted, so `/api/v1/...` now returns `404`.

## Endpoints

- `POST /v1/device/register`
- `POST /v1/device/login`
- `POST /v1/telemetry`
- `GET /v1/device/config`
- `GET /v1/ota/latest`
- `GET /v1/dashboard/devices/:deviceId/telemetry/history`
- `GET /v1/dashboard/devices/:deviceId/ota/history`
- `GET /v1/dashboard/firmware/releases`
