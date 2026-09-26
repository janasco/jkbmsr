#pragma once

#include <Arduino.h>

namespace jkbmsr {

struct OtaStatus {
  uint32_t lastCheckAtMs = 0;
  bool lastCheckSucceeded = false;
  bool updateAvailable = false;
  bool updateApplied = false;
  String offeredVersion;
  String lastResult = "idle";
};

class OtaClient {
 public:
  explicit OtaClient(String apiBaseUrl);
  // `versionFloor` is the highest version this device has ever run; an offered
  // release is applied only if it is strictly newer than the floor
  // (anti-rollback), on top of signature + checksum verification.
  bool checkForUpdate(const String& token, const String& currentVersion, const String& versionFloor);
  const OtaStatus& status() const;

 private:
  void setStatus(
      uint32_t lastCheckAtMs,
      bool lastCheckSucceeded,
      bool updateAvailable,
      bool updateApplied,
      const String& offeredVersion,
      const String& lastResult);

  String apiBaseUrl_;
  OtaStatus status_;
};

}  // namespace jkbmsr
