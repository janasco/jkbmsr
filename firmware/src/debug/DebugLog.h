#pragma once

#include <Arduino.h>

namespace jkbmsr {

// Improv Serial provisioning shares UART0 with these logs; text written mid
// handshake corrupts the binary protocol stream. Disable logging for the
// duration of provisioning and re-enable afterwards.
void setLoggingEnabled(bool enabled);

void logInfo(const String& message);
void logWarn(const String& message);
void logError(const String& message);

}  // namespace jkbmsr
