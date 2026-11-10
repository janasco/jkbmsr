#include "DebugLog.h"

#include <time.h>

namespace jkbmsr {

namespace {

bool g_loggingEnabled = true;

// Anything before 2024-01-01 means NTP has not answered yet.
constexpr time_t kMinimumSaneEpoch = 1704067200;

void printTimestamp() {
  const time_t now = time(nullptr);
  if (now < kMinimumSaneEpoch) {
    // Before the first NTP answer there is no wall clock, and printing a fake
    // 1970 time would be worse than saying so. Seconds since boot are honest and
    // still let two lines be ordered.
    Serial.print("[+");
    Serial.print(static_cast<unsigned long>(millis() / 1000));
    Serial.print("s] ");
    return;
  }
  struct tm local {};
  localtime_r(&now, &local);
  char buffer[20];
  if (strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &local) == 0) {
    Serial.print("[time?] ");
    return;
  }
  Serial.print("[");
  Serial.print(buffer);
  Serial.print("] ");
}

void logWithLevel(const char* level, const String& message) {
  if (!g_loggingEnabled) {
    return;
  }
  Serial.print("[");
  Serial.print(level);
  Serial.print("] ");
  printTimestamp();
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
