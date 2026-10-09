#include "WifiManager.h"

#if defined(ARDUINO_ARCH_ESP8266)
#include <ESP8266WiFi.h>
#else
#include <WiFi.h>
#endif
#include "debug/DebugLog.h"

namespace jkbmsr {

bool WifiManager::connect(const String& ssid, const String& password, uint32_t timeoutMs) {
  if (ssid.length() == 0) {
    logWarn("WiFi SSID is not configured");
    return false;
  }

  // Keep SoftAP alive when the captive portal is up (AP or AP_STA); otherwise
  // switch to station-only so a normal boot doesn't leave an open AP around.
  // `auto` rather than naming the return type: it's wifi_mode_t (esp-idf) on
  // ESP32 but WiFiMode_t (ESP8266 core) — different type name, same values.
  const auto mode = WiFi.getMode();
  if (mode == WIFI_AP || mode == WIFI_AP_STA) {
    WiFi.mode(WIFI_AP_STA);
  } else {
    WiFi.mode(WIFI_STA);
  }
  connecting_ = true;
  WiFi.disconnect(false, false);
  WiFi.begin(ssid.c_str(), password.length() > 0 ? password.c_str() : nullptr);

  const uint32_t startMs = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startMs < timeoutMs) {
    delay(250);
  }
  connecting_ = false;

  const bool connectedNow = WiFi.status() == WL_CONNECTED;
  if (!connectedNow) {
    // Distinguishes "wrong password / AP not found" (status stays at an
    // early value) from "associated fine but DHCP never finished" (status
    // is WL_IDLE_STATUS/WL_DISCONNECTED despite the driver's own log
    // already having reported L2 association) -- see kWifiConnectTimeoutMs.
    lastError_ = "connect timed out; WiFi.status()=" + String(WiFi.status());
    logWarn("WiFi " + lastError_);
  } else {
    lastError_ = "";
  }
  return connectedNow;
}

bool WifiManager::connected() const {
  return WiFi.status() == WL_CONNECTED;
}

size_t WifiManager::scan(WifiScanResult* results, size_t capacity) {
  if (results == nullptr || capacity == 0) return 0;

  if (connecting_) {
    // A connect() call from either provisioning path (Improv Serial and the
    // SoftAP captive portal are polled in parallel by runProvisioning()) is
    // already in flight on this same STA interface. The ESP32 WiFi driver
    // rejects a scan outright while STA is connecting ("STA is connecting,
    // scan are not allowed") -- confirmed on real hardware (2026-08-21) as
    // the actual cause of the "step 6 stuck, no networks listed" bug: a scan
    // landing during a connect from the other path silently failed with no
    // error surfaced to the browser.
    logWarn("WiFi scan skipped: a connect attempt is already in progress");
    return 0;
  }

  int count = -1;
  for (int attempt = 0; attempt < 3 && count < 0; ++attempt) {
    if (attempt > 0) {
      // connecting_ above only covers overlap with a connect() call this
      // class made; the driver's own internal STA state can still be
      // settling for a brief window right after a connect attempt (from
      // either path) finishes. Retry instead of surfacing that one
      // transient rejection as "no networks found".
      delay(300);
    }
#if defined(ARDUINO_ARCH_ESP8266)
    // ESP8266 core's scanNetworks() has a narrower signature (no passive-scan
    // or per-channel-timing params) — (async, show_hidden, channel, ssid);
    // channel=0 scans all channels, matching the ESP32 call's intent below.
    count = WiFi.scanNetworks(false, true, 0);
#else
    count = WiFi.scanNetworks(false, true, false, 300, 0);
#endif
  }
  if (count <= 0) {
    WiFi.scanDelete();
    return 0;
  }

  size_t written = 0;
  for (int index = 0; index < count && written < capacity; ++index) {
    const String ssid = WiFi.SSID(index);
    if (ssid.length() == 0) continue;
    bool duplicate = false;
    for (size_t existing = 0; existing < written; ++existing) {
      if (results[existing].ssid == ssid) {
        if (WiFi.RSSI(index) > results[existing].rssi) results[existing].rssi = WiFi.RSSI(index);
        duplicate = true;
        break;
      }
    }
    if (duplicate) continue;
    results[written].ssid = ssid;
    results[written].rssi = WiFi.RSSI(index);
#if defined(ARDUINO_ARCH_ESP8266)
    // ESP8266 core's WiFi.encryptionType() returns wl_enc_type, not
    // esp-idf's wifi_auth_mode_t — different enum, different "open" value.
    results[written].secure = WiFi.encryptionType(index) != ENC_TYPE_NONE;
#else
    results[written].secure = WiFi.encryptionType(index) != WIFI_AUTH_OPEN;
#endif
    ++written;
  }
  WiFi.scanDelete();
  return written;
}

String WifiManager::currentSsid() const {
  return connected() ? WiFi.SSID() : String();
}

}  // namespace jkbmsr
