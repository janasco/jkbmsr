#include "OtaClient.h"

#if defined(ARDUINO_ARCH_ESP8266)

#include "debug/DebugLog.h"

namespace jkbmsr {

OtaClient::OtaClient(String apiBaseUrl) : apiBaseUrl_(apiBaseUrl) {}

const OtaStatus& OtaClient::status() const {
  return status_;
}

void OtaClient::setStatus(
    uint32_t lastCheckAtMs,
    bool lastCheckSucceeded,
    bool updateAvailable,
    bool updateApplied,
    const String& offeredVersion,
    const String& lastResult) {
  status_.lastCheckAtMs = lastCheckAtMs;
  status_.lastCheckSucceeded = lastCheckSucceeded;
  status_.updateAvailable = updateAvailable;
  status_.updateApplied = updateApplied;
  status_.offeredVersion = offeredVersion;
  status_.lastResult = lastResult;
}

bool OtaClient::checkForUpdate(
    const String& /*token*/,
    const String& /*currentVersion*/,
    const String& /*versionFloor*/) {
  logWarn("OTA is not enabled for this experimental hardware target");
  setStatus(millis(), false, false, false, "", "unsupported-on-hardware-target");
  return false;
}

}  // namespace jkbmsr

#endif
