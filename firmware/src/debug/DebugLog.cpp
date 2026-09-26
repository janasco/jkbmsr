#include "DebugLog.h"

namespace jkbmsr {

namespace {

bool g_loggingEnabled = true;

void logWithLevel(const char* level, const String& message) {
  if (!g_loggingEnabled) {
    return;
  }
  Serial.print("[");
  Serial.print(level);
  Serial.print("] ");
  Serial.println(message);
}

}  // namespace

void setLoggingEnabled(bool enabled) {
  g_loggingEnabled = enabled;
}

void logInfo(const String& message) {
  logWithLevel("info", message);
}

void logWarn(const String& message) {
  logWithLevel("warn", message);
}

void logError(const String& message) {
  logWithLevel("error", message);
}

}  // namespace jkbmsr
