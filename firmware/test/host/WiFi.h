#pragma once
// Minimal WiFi host shim — NOT the arduino-esp32 WiFi library.
//
// Why: provisioning/CaptivePortal.cpp raises a SoftAP and device/
// DeviceIdentity.cpp reads the factory efuse MAC, so both need the WiFi/
// ESP surface. test/test_provisioning only calls CaptivePortal's static
// helpers (softApSsid/softApPassword), which is why this can be inert: every
// call below is a no-op that reports "not connected" and a fixed MAC. Nothing
// in the host run may depend on a real association.
//
// This is a test scaffold only. It must never be on the include path for a real
// firmware build — src/ includes <WiFi.h> by that exact name, so shadowing it
// would compile a gateway that never radios.

#include <cstdint>

#include <Arduino.h>  // String

// Arduino keeps IPAddress in WiFi.h, not in the core Arduino.h.
class IPAddress {
 public:
  IPAddress() = default;
  IPAddress(uint8_t a, uint8_t b, uint8_t c, uint8_t d) : octets_{a, b, c, d} {}
  explicit IPAddress(uint32_t raw) : octets_{static_cast<uint8_t>(raw), static_cast<uint8_t>(raw >> 8),
                                             static_cast<uint8_t>(raw >> 16),
                                             static_cast<uint8_t>(raw >> 24)} {}

  operator uint32_t() const {
    return static_cast<uint32_t>(octets_[0]) | (static_cast<uint32_t>(octets_[1]) << 8) |
           (static_cast<uint32_t>(octets_[2]) << 16) | (static_cast<uint32_t>(octets_[3]) << 24);
  }

  String toString() const {
    return String(std::to_string(octets_[0]) + "." + std::to_string(octets_[1]) + "." +
                  std::to_string(octets_[2]) + "." + std::to_string(octets_[3]));
  }

 private:
  uint8_t octets_[4] = {0, 0, 0, 0};
};

enum wl_status_t : uint8_t {
  WL_NO_SHIELD = 255,
  WL_IDLE_STATUS = 0,
  WL_NO_SSID_AVAIL = 1,
  WL_SCAN_COMPLETED = 2,
  WL_CONNECTED = 3,
  WL_CONNECT_FAILED = 4,
  WL_CONNECTION_LOST = 5,
  WL_DISCONNECTED = 6,
};

// WiFi.mode() argument bits (mirrors the core's wifi_mode_t).
#define WIFI_OFF 0
#define WIFI_STA 1
#define WIFI_AP 2
#define WIFI_AP_STA (WIFI_AP | WIFI_STA)

class WiFiClass {
 public:
  bool mode(uint8_t) { return true; }
  bool softAPConfig(const IPAddress& local, const IPAddress& gateway, const IPAddress& subnet) {
    (void)local;
    (void)gateway;
    (void)subnet;
    return true;
  }
  bool softAP(const char* ssid, const char* password = nullptr) {
    (void)ssid;
    (void)password;
    return true;
  }
  bool softAPdisconnect(bool wifioff = false) {
    (void)wifioff;
    return true;
  }
  // Never associated: CaptivePortal::end() only consults this to decide whether
  // to fall back to station-only mode.
  wl_status_t status() { return WL_DISCONNECTED; }
};

extern WiFiClass WiFi;

// The core's `ESP` chip object. Only the two accessors DeviceIdentity uses are
// provided; the efuse MAC is a fixed non-zero value so hardwareFingerprint()
// returns the same "unknown"-avoiding path a real chip takes.
class EspClass {
 public:
  uint64_t getEfuseMac() { return 0x001122334455ULL; }
  const char* getChipModel() { return "esp32-host-stub"; }
};

extern EspClass ESP;
