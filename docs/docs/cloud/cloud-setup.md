# Cloud Setup

JKBMSR Cloud runs on Cloudflare Workers with D1 for database storage and R2 for firmware files.

## Components

- Cloudflare Workers for the API.
- Cloudflare D1 for devices, telemetry, alerts, firmware metadata, and users.
- Cloudflare R2 for OTA firmware binaries.
- Cloudflare Pages for the web dashboard.
