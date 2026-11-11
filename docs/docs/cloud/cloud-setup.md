# Cloud Setup

JKBMSR Cloud runs on managed serverless infrastructure: a hosted API, a managed database, and private firmware storage, and no self-managed servers.

## Components

- Hosted API serving the gateways, apps, and dashboard.
- Managed database for devices, telemetry, alerts, firmware metadata, and users.
- Private storage for OTA firmware binaries.
- Hosted static hosting for the web dashboard.

## Gateway settings

The dashboard holds the settings for each gateway. They are sent to the device on
its next check-in, so a change applies within about a minute and never needs a
reboot.

| Setting | What it does |
|---|---|
| Telemetry interval | How often the gateway reports. The fastest value available depends on your Cloud Service tier; the free tier reports hourly. |
| Gateway time zone | How the gateway renders times in its own serial log. See below. |
| BMS Bluetooth address | Pins the gateway to one pack when more than one is in range. Leave it empty to connect to the strongest advertisement it recognises. |
| WiFi target | Moves the gateway to another network remotely, for example after a router change. |

### Gateway time zone

Telemetry is always stored in UTC, so a customer in one country and a support
engineer in another read the same data. The time zone setting only decides how
the gateway renders times **in its own serial log**, which is what you see while
flashing or watching the console.

Pick your zone under **Settings → General → Gateway time zone**. The value is a
POSIX time zone string rather than an IANA name, because the ESP32 has no time
zone database on board and cannot resolve a name like `Asia/Manila`. The picker
maps a readable label to the string the device understands.

Before the first clock sync the log prints seconds since boot (`[+12s]`) rather
than a made-up date, because there is no clock to read yet.
