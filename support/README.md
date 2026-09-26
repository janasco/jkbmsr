# JKBMSR Support & Compatibility Community

This repo is the community hub for [JKBMSR](https://jkbmsr.com) — the place to
report bugs, report and confirm whether a specific BMS model works with
JKBMSR firmware, and discuss anything else related to setup, wiring, or
firmware behavior.

There's no code here. Everything happens in **[Discussions](../discussions)**
and **[Issues](../issues)**.

## Reporting a bug

Bugs across the JKBMSR products are reported **here**, not in each
product's own repo — [open a new issue](../issues/new/choose) and pick the
template for the affected area:

- **Firmware** — the ESP32 gateway firmware
- **Web app / dashboard** — jkbmsr.com and the authenticated dashboard
- **Mobile app** — the Android/iOS app

Each template applies the matching label (`firmware`, `web-app`, or
`mobile-app`) automatically. If you're not sure whether your BMS model is
supported at all, that's a compatibility question for Discussions below, not
a bug report.

## Compatibility discussions

JKBMSR supports **JK-BMS only**. Other BMS vendors are not currently
supported — check [jkbmsr.com/compatibility](https://jkbmsr.com/compatibility)
for the current list before opening a discussion about another brand.

Discussions are organized into one category per JK-BMS model family:

- **JK-BMS — JK02 series (24S/32S)**
- **JK-BMS — JK04 series and newer**
- **JK-BMS — model not listed / identification help**

If you've tried JKBMSR with a specific model, open a new discussion in that
category with the exact model number in the title (e.g.
`JK-B2A24S — confirmed working over Bluetooth`) and describe what you tested
(connection type, cell count, firmware version, what worked and what didn't).
Other owners with the same or a similar model can reply and confirm.

## How this feeds back into the site

Reports confirmed in Discussions are what's behind the **Community Verified**
labels on [jkbmsr.com/compatibility](https://jkbmsr.com/compatibility). A
model showing up there as community-verified means real owners reported it
working, not that JKBMSR's maintainer tested that exact unit.
