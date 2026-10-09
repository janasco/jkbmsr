#include "ConfigStore.h"

#if defined(ARDUINO_ARCH_ESP8266)
#include <ArduinoJson.h>
#include <LittleFS.h>
#else
#include <Preferences.h>
#endif

namespace jkbmsr {

namespace {

constexpr const char* kNamespace = "jkbmsr";
#if defined(ARDUINO_ARCH_ESP8266)
constexpr const char* kConfigPath = "/jkbmsr-config.json";
constexpr const char* kConfigTempPath = "/jkbmsr-config.tmp";
#endif

}  // namespace

bool ConfigStore::begin() {
#if defined(ARDUINO_ARCH_ESP8266)
  return LittleFS.begin();
#else
  Preferences prefs;
  const bool ok = prefs.begin(kNamespace, false);
  prefs.end();
  return ok;
#endif
}

DeviceConfig ConfigStore::load() {
#if defined(ARDUINO_ARCH_ESP8266)
  DeviceConfig config;
  File file = LittleFS.open(kConfigPath, "r");
  if (!file) return config;

  JsonDocument document;
  const DeserializationError error = deserializeJson(document, file);
  file.close();
  if (error) return config;

  config.deviceId = document["deviceId"] | "";
  config.firmwareVersionFloor = document["firmwareVersionFloor"] | "";
  config.wifiSsid = document["wifiSsid"] | "";
  config.wifiPassword = document["wifiPassword"] | "";
  config.deviceToken = document["deviceToken"] | "";
  config.deviceSecret = document["deviceSecret"] | "";
  config.claimCode = document["claimCode"] | "";
  config.wifiDesiredRevision = document["wifiDesiredRevision"] | "";
  config.wifiLocalProvisioned = document["wifiLocalProvisioned"] | config.wifiLocalProvisioned;
  config.wifiRestartCount = document["wifiRestartCount"] | config.wifiRestartCount;
  config.telemetryIntervalMs = document["telemetryIntervalMs"] | config.telemetryIntervalMs;
  config.otaEnabled = document["otaEnabled"] | config.otaEnabled;
  config.bmsVendor = document["bmsVendor"] | config.bmsVendor;
  config.bmsUartRxPin = document["bmsUartRxPin"] | config.bmsUartRxPin;
  config.bmsUartTxPin = document["bmsUartTxPin"] | config.bmsUartTxPin;
  config.bmsUartBaudRate = document["bmsUartBaudRate"] | config.bmsUartBaudRate;
  config.bmsUartCaptureEnabled = document["bmsUartCaptureEnabled"] | config.bmsUartCaptureEnabled;
  config.bmsBleEnabled = false;
  config.bmsBleAddress = "";
  return config;
#else
  Preferences prefs;
  DeviceConfig config;
  if (!prefs.begin(kNamespace, true)) {
    return config;
  }

  config.deviceId = prefs.getString("device_id", "");
  config.firmwareVersionFloor = prefs.getString("fw_floor", "");
  config.wifiSsid = prefs.getString("wifi_ssid", "");
  config.wifiPassword = prefs.getString("wifi_pass", "");
  config.deviceToken = prefs.getString("jwt", "");
  config.deviceSecret = prefs.getString("dev_secret", "");
  config.claimCode = prefs.getString("claim_code", "");
  config.wifiDesiredRevision = prefs.getString("wifi_des_rev", "");
  config.wifiLocalProvisioned = prefs.getBool("wifi_local", config.wifiLocalProvisioned);
  config.wifiRestartCount = prefs.getUInt("wifi_restart", config.wifiRestartCount);
  config.telemetryIntervalMs = prefs.getUInt("interval_ms", config.telemetryIntervalMs);
  config.otaEnabled = prefs.getBool("ota_enabled", config.otaEnabled);
  config.bmsVendor = prefs.getString("bms_vendor", config.bmsVendor);
  config.bmsUartRxPin = prefs.getInt("bms_rx_pin", config.bmsUartRxPin);
  config.bmsUartTxPin = prefs.getInt("bms_tx_pin", config.bmsUartTxPin);
  config.bmsUartBaudRate = prefs.getUInt("bms_baud", config.bmsUartBaudRate);
  config.bmsUartCaptureEnabled = prefs.getBool("bms_capture", config.bmsUartCaptureEnabled);
  config.bmsBleEnabled = prefs.getBool("bms_ble_en", config.bmsBleEnabled);
  config.bmsBleAddress = prefs.getString("bms_ble_addr", "");
  prefs.end();
  return config;
#endif
}

bool ConfigStore::save(const DeviceConfig& config) {
#if defined(ARDUINO_ARCH_ESP8266)
  JsonDocument document;
  document["deviceId"] = config.deviceId;
  document["firmwareVersionFloor"] = config.firmwareVersionFloor;
  document["wifiSsid"] = config.wifiSsid;
  document["wifiPassword"] = config.wifiPassword;
  document["deviceToken"] = config.deviceToken;
  document["deviceSecret"] = config.deviceSecret;
  document["claimCode"] = config.claimCode;
  document["wifiDesiredRevision"] = config.wifiDesiredRevision;
  document["wifiLocalProvisioned"] = config.wifiLocalProvisioned;
  document["wifiRestartCount"] = config.wifiRestartCount;
  document["telemetryIntervalMs"] = config.telemetryIntervalMs;
  document["otaEnabled"] = false;
  document["bmsVendor"] = config.bmsVendor;
  document["bmsUartRxPin"] = config.bmsUartRxPin;
  document["bmsUartTxPin"] = config.bmsUartTxPin;
  document["bmsUartBaudRate"] = config.bmsUartBaudRate;
  document["bmsUartCaptureEnabled"] = config.bmsUartCaptureEnabled;

  File file = LittleFS.open(kConfigTempPath, "w");
  if (!file) return false;
  const bool written = serializeJson(document, file) > 0;
  file.flush();
  file.close();
  if (!written) {
    LittleFS.remove(kConfigTempPath);
    return false;
  }
  LittleFS.remove(kConfigPath);
  return LittleFS.rename(kConfigTempPath, kConfigPath);
#else
  Preferences prefs;
  if (!prefs.begin(kNamespace, false)) {
    return false;
  }

  bool ok = true;
  ok &= prefs.putString("device_id", config.deviceId) > 0;
  ok &= prefs.putString("fw_floor", config.firmwareVersionFloor) > 0;
  ok &= prefs.putString("wifi_ssid", config.wifiSsid) > 0;
  ok &= prefs.putString("wifi_pass", config.wifiPassword) > 0;
  ok &= prefs.putString("jwt", config.deviceToken) > 0;
  ok &= prefs.putString("dev_secret", config.deviceSecret) > 0;
  ok &= prefs.putString("claim_code", config.claimCode) > 0;
  ok &= prefs.putString("wifi_des_rev", config.wifiDesiredRevision) > 0;
  ok &= prefs.putBool("wifi_local", config.wifiLocalProvisioned) > 0;
  ok &= prefs.putUInt("wifi_restart", config.wifiRestartCount) > 0;
  ok &= prefs.putUInt("interval_ms", config.telemetryIntervalMs) > 0;
  ok &= prefs.putBool("ota_enabled", config.otaEnabled) > 0;
  ok &= prefs.putString("bms_vendor", config.bmsVendor) > 0;
  ok &= prefs.putInt("bms_rx_pin", config.bmsUartRxPin) > 0;
  ok &= prefs.putInt("bms_tx_pin", config.bmsUartTxPin) > 0;
  ok &= prefs.putUInt("bms_baud", config.bmsUartBaudRate) > 0;
  ok &= prefs.putBool("bms_capture", config.bmsUartCaptureEnabled) > 0;
  ok &= prefs.putBool("bms_ble_en", config.bmsBleEnabled) > 0;
  ok &= prefs.putString("bms_ble_addr", config.bmsBleAddress) > 0;
  prefs.end();
  return ok;
#endif
}

}  // namespace jkbmsr
