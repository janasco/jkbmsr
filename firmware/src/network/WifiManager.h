#pragma once

#include <Arduino.h>

namespace jkbmsr {

constexpr size_t kMaxWifiScanResults = 20;

struct WifiScanResult {
  String ssid;
  int32_t rssi = -127;
  bool secure = true;
};

class WifiManager {
 public:
  bool connect(const String& ssid, const String& password, uint32_t timeoutMs);
  bool connected() const;
  size_t scan(WifiScanResult* results, size_t capacity);
  String currentSsid() const;

 private:
  // Guards against Improv Serial and the SoftAP captive portal -- polled in
  // parallel by runProvisioning() -- racing a scan against a connect
  // attempt on the same STA interface. See WifiManager::scan().
  bool connecting_ = false;
};

}  // namespace jkbmsr
