#pragma once

#include <Arduino.h>
#include "config/ConfigStore.h"

namespace jkbmsr {

struct DeviceRegistrationResult {
  String token;
  String deviceSecret;
  uint32_t telemetryIntervalMs = 60000;
  bool otaEnabled = true;
  String bmsVendor = "jk";
  int bmsUartRxPin = 16;
  int bmsUartTxPin = 17;
  uint32_t bmsUartBaudRate = 115200;
  bool bmsUartCaptureEnabled = false;
};

class DeviceRegistrationClient {
 public:
  explicit DeviceRegistrationClient(String apiBaseUrl);
  // targetHardware/hardwarePlatform are validated server-side against
  // jkbmsr-api's gatewayHardwareTargets catalog (src/routes/device.ts) —
  // must match one of its registered targetHardware ids and that target's
  // own platform field exactly, or registration is rejected.
  bool registerDevice(
      const String& deviceId,
      const String& hardwareId,
      const String& hardwareFingerprint,
      const String& hardwarePlatform,
      const String& hardwareModel,
      const String& targetHardware,
      const String& boardProfile,
      const String& firmwareVersion,
      const String& claimCode,
      const String& claimToken,
      DeviceRegistrationResult& result);
  bool loginDevice(
      const String& deviceId,
      const String& deviceSecret,
      const String& hardwareFingerprint,
      const String& hardwarePlatform,
      const String& hardwareModel,
      const String& targetHardware,
      const String& boardProfile,
      const String& firmwareVersion,
      DeviceRegistrationResult& result);

 private:
  String apiBaseUrl_;
};

}  // namespace jkbmsr
