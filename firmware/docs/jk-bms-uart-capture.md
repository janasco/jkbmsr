# JK-BMS UART Capture Workflow

Use this workflow to validate the parser against real JK-BMS frames.

## Enable Capture

1. Open the device settings page in the web dashboard.
2. Confirm the JK-BMS UART RX pin, TX pin, and baud rate.
3. Enable `Raw UART capture logging enabled`.
4. Wait for the device to fetch remote config, or reboot the device after saving settings.

When enabled, firmware writes raw UART batches to USB serial:

```text
JKBMSR_UART_CAPTURE <millis> <byte_count> <hex bytes...>
```

Example:

```text
JKBMSR_UART_CAPTURE 18422 8 4E 57 00 20 79 04 01 0C
```

## Capture From USB Serial

Use PlatformIO serial monitor:

```sh
pio device monitor --baud 115200
```

Save at least 30 seconds of output while the BMS is active. Keep both successful telemetry uploads and capture lines.

## Validation Rules

For each capture set:

1. Merge consecutive `JKBMSR_UART_CAPTURE` hex byte lines in timestamp order.
2. Find complete frames beginning with `4E 57`.
3. Compare parsed values against the JK-BMS app or display:
   - pack voltage
   - pack current
   - state of charge
   - temperature sensors
   - every cell voltage
4. Add the complete raw frame as a fixture under `test/test_jk_bms_parser`.
5. Add assertions for all values that can be confirmed from the BMS app.

## Safety

Disable raw capture after collecting samples. It is verbose and should not be left on for normal operation.

Checksum validation should only be added after real captured frames confirm the exact checksum range and byte order.
