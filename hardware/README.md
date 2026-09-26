# jkbmsr-hardware

Hardware planning workspace for JKBMSR ESP32 gateways.

The overall JKBMSR product is now in execution with firmware, cloud, web dashboard, and OTA release infrastructure. This repository remains hardware planning only: it contains design notes, connector planning, BOM drafts, wiring guidance, and enclosure notes, but no production PCB files yet.

## Role In The System

`jkbmsr-hardware` defines the physical gateway that connects a JK-BMS UART port to JKBMSR Cloud through ESP32 firmware.

Planned hardware responsibilities:

- Provide a reliable ESP32 gateway board.
- Connect safely to JK-BMS UART.
- Provide stable power input.
- Support USB-C programming and service.
- Provide status LEDs.
- Fit a practical enclosure.
- Keep wiring simple for installers and battery owners.

## Current Status

- Planning documentation exists.
- No PCB files are included yet.
- No manufacturing outputs are included yet.
- No validated enclosure files are included yet.

## Initial Hardware: JKBMSR Mini

Planned features:

- ESP32
- UART connection to JK-BMS
- Buck converter input
- USB-C power/programming
- Status LEDs
- Reset and boot buttons
- JST connector for BMS port

## Future Hardware: JKBMSR Pro

Possible later features:

- ESP32
- RS485
- CAN
- Ethernet
- Isolated power
- More robust enclosure
- Industrial connector options

## Hardware Scope

Version 1 is for JK-BMS only.

Do not design hardware around Daly, JBD, Seplos, or other BMS vendors yet unless explicitly scoped as future work.

## Documentation

- [PCB planning](docs/pcb-planning.md)
- [Connector pinout](docs/connector-pinout.md)
- [Safety notes](docs/safety-notes.md)
- [BOM draft](docs/bom-draft.md)
- [Enclosure notes](docs/enclosure-notes.md)
- [Wiring diagrams](wiring-diagrams/README.md)

## Related Repositories

- `jkbmsr-firmware`: ESP32 firmware that will run on this hardware.
- `jkbmsr-api`: backend API and OTA firmware delivery.
- `jkbmsr-web`: deployed customer dashboard, public site, and documentation (`jkbmsr.com/docs`).

## Safety Notes

- Battery systems can be dangerous.
- Wiring mistakes can damage hardware or create unsafe battery conditions.
- UART voltage levels must be verified before connection.
- Power input and grounding need careful validation.
- Production hardware should be reviewed before field use.

## Next Work

- Finalize JK-BMS connector pinout assumptions.
- Choose exact ESP32 module/package.
- Draft schematic.
- Draft PCB layout.
- Validate power input design.
- Validate UART level compatibility.
- Create first prototype BOM.
- Add enclosure CAD once board dimensions stabilize.
