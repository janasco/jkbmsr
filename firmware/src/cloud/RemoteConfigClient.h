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
  // Persistent remote Wi-Fi target (see backend services/wifiConfigs.ts). The
  // gateway applies it when desiredRevision differs from what it last applied.
  String desiredSsid;
  String desiredPassword;
  bool desiredOpen = false;
  String desiredRevision;
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
  // Reports the gateway's own Wi-Fi state while it can reach the cloud, so the
  // backend can tell "reached the cloud on the new network" apart from "not
  // seen at all". localProvisioned is the one-shot override flag (see
  // DeviceConfig::wifiLocalProvisioned).
  bool reportWifiState(const String& token, const String& state, const String& currentSsid,
                       const String& lastError, bool localProvisioned);
  bool reportOtaCommand(const String& token, const String& requestId, const String& status,
                        const String& message);

 private:
  String apiBaseUrl_;
};

}  // namespace jkbmsr
