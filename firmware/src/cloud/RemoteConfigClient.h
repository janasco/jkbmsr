#pragma once

#include <Arduino.h>
#include "config/ConfigStore.h"
#include "network/WifiManager.h"

namespace jkbmsr {

struct RemoteWifiActions {
  String scanRequestId;
  String changeRequestId;
  String candidateSsid;
  String candidatePassword;
  String otaUpdateRequestId;
};

class RemoteConfigClient {
 public:
  explicit RemoteConfigClient(String apiBaseUrl);
  bool fetch(const String& token, DeviceConfig& config, RemoteWifiActions* wifiActions = nullptr);
  bool reportWifiScan(const String& token, const String& requestId, const String& currentSsid,
                      const WifiScanResult* results, size_t count);
  bool reportWifiChange(const String& token, const String& requestId, const String& status,
                        const String& currentSsid, const String& message);
  bool reportOtaCommand(const String& token, const String& requestId, const String& status,
                        const String& message);

 private:
  String apiBaseUrl_;
};

}  // namespace jkbmsr
