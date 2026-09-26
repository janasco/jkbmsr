#pragma once

#include <stdint.h>

namespace jkbmsr {

// The complete JK02 BLE command surface allowed by JKBMSR. These commands
// request snapshots/streaming only; configuration writes are intentionally not
// representable by this type.
enum class JkBmsReadOnlyCommand : uint8_t {
  kSettingsAndTelemetryStream = 0x96,
  kDeviceInfo = 0x97,
};

constexpr bool isJkBmsReadOnlyCommand(uint8_t value) {
  return value == static_cast<uint8_t>(JkBmsReadOnlyCommand::kSettingsAndTelemetryStream) ||
         value == static_cast<uint8_t>(JkBmsReadOnlyCommand::kDeviceInfo);
}

}  // namespace jkbmsr
