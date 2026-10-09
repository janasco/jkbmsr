#include "RemoteConfigClient.h"

#include <ArduinoJson.h>
#if defined(ARDUINO_ARCH_ESP8266)
#include <ESP8266HTTPClient.h>
#else
#include <HTTPClient.h>
#endif
#include <WiFiClientSecure.h>

#include "debug/DebugLog.h"
#include "net/PlatformNetwork.h"
#include "net/SecureClient.h"

namespace jkbmsr {

RemoteConfigClient::RemoteConfigClient(String apiBaseUrl) : apiBaseUrl_(apiBaseUrl) {}

bool RemoteConfigClient::fetch(const String& token, DeviceConfig& config, RemoteWifiActions* wifiActions) {
  if (token.length() == 0) {
    logWarn("Remote config skipped because device token is missing");
    return false;
  }

  GatewaySecureClient client;
  configureSecureClient(client);

  HTTPClient http;
  const String url = apiBaseUrl_ + "/api/v1/device/config";
  if (!http.begin(client, url)) {
    logError("Remote config request could not start");
    return false;
  }

  http.addHeader("Authorization", "Bearer " + token);
  const int status = http.GET();
  if (status != HTTP_CODE_OK) {
    logWarn("Remote config request failed with status " + String(status));
    http.end();
    return false;
  }

  JsonDocument document;
  const DeserializationError error = deserializeJson(document, http.getString());
  http.end();
  if (error) {
    logError("Remote config JSON parse failed");
    return false;
  }

  // Range matches the full Cloud Service tier spectrum (10s fastest paid
  // tier to 3600s/1hr free tier -- see jkbmsr-api's subscriptionTiers.ts,
  // CLOUD_SERVICE_TIERS[0]). This used to be clamped to 60-300s, then
  // 10-1800s once the free tier still ran a 30-minute interval; when the
  // free tier moved to 1 hour (2026-08-11) this clamp's upper bound wasn't
  // updated to match, so free-tier gateways were silently reporting twice
  // as often as intended. Keep this in sync with the identical clamp in
  // DeviceRegistrationClient.cpp.
  const uint32_t intervalSeconds = document["telemetryIntervalSeconds"] | 60;
  config.telemetryIntervalMs = constrain(intervalSeconds, 10U, 3600U) * 1000;
  config.otaEnabled = document["otaEnabled"] | true;
  config.bmsVendor = document["bmsVendor"] | config.bmsVendor;
  config.bmsUartRxPin = document["bmsUartRxPin"] | config.bmsUartRxPin;
  config.bmsUartTxPin = document["bmsUartTxPin"] | config.bmsUartTxPin;
  config.bmsUartBaudRate = document["bmsUartBaudRate"] | config.bmsUartBaudRate;
  config.bmsUartCaptureEnabled = document["bmsUartCaptureEnabled"] | config.bmsUartCaptureEnabled;
  config.bmsBleEnabled = document["bmsBleEnabled"] | config.bmsBleEnabled;
  config.bmsBleAddress = document["bmsBleAddress"] | config.bmsBleAddress;
  if (wifiActions != nullptr) {
    wifiActions->scanRequestId = document["wifiScanRequestId"] | "";
    wifiActions->changeRequestId = document["wifiChange"]["requestId"] | "";
    wifiActions->candidateSsid = document["wifiChange"]["ssid"] | "";
    wifiActions->candidatePassword = document["wifiChange"]["password"] | "";
    wifiActions->desiredSsid = document["wifiDesired"]["ssid"] | "";
    wifiActions->desiredPassword = document["wifiDesired"]["password"] | "";
    wifiActions->desiredOpen = document["wifiDesired"]["isOpen"] | false;
    wifiActions->desiredRevision = document["wifiDesired"]["revision"] | "";
    wifiActions->otaUpdateRequestId = document["otaUpdateRequestId"] | "";
  }
  logInfo("Remote config applied");
  return true;
}

namespace {

bool postWifiStatus(const String& apiBaseUrl, const String& token, JsonDocument& document) {
  GatewaySecureClient client;
  configureSecureClient(client);
  HTTPClient http;
  if (!http.begin(client, apiBaseUrl + "/api/v1/device/wifi/status")) return false;
  http.addHeader("Authorization", "Bearer " + token);
  http.addHeader("Content-Type", "application/json");
  String payload;
  serializeJson(document, payload);
  const int status = http.POST(payload);
  http.end();
  return status >= 200 && status < 300;
}

}  // namespace

bool RemoteConfigClient::reportWifiScan(const String& token, const String& requestId,
                                        const String& currentSsid, const WifiScanResult* results,
                                        size_t count) {
  JsonDocument document;
  document["scanRequestId"] = requestId;
  document["currentSsid"] = currentSsid;
  JsonArray networks = document["networks"].to<JsonArray>();
  for (size_t index = 0; index < count; ++index) {
    JsonObject network = networks.add<JsonObject>();
    network["ssid"] = results[index].ssid;
    network["rssi"] = results[index].rssi;
    network["secure"] = results[index].secure;
  }
  return postWifiStatus(apiBaseUrl_, token, document);
}

bool RemoteConfigClient::reportWifiChange(const String& token, const String& requestId,
                                          const String& status, const String& currentSsid,
                                          const String& message) {
  JsonDocument document;
  document["changeRequestId"] = requestId;
  document["status"] = status;
  document["currentSsid"] = currentSsid;
  document["message"] = message;
  return postWifiStatus(apiBaseUrl_, token, document);
}

bool RemoteConfigClient::reportWifiState(const String& token, const String& state,
                                         const String& currentSsid, const String& lastError,
                                         bool localProvisioned) {
  JsonDocument document;
  document["state"] = state;
  document["currentSsid"] = currentSsid;
  document["lastError"] = lastError;
  if (localProvisioned) {
    document["localProvisioned"] = true;
  }
  return postWifiStatus(apiBaseUrl_, token, document);
}

bool RemoteConfigClient::reportOtaCommand(const String& token, const String& requestId,
                                          const String& status, const String& message) {
  GatewaySecureClient client;
  configureSecureClient(client);
  HTTPClient http;
  if (!http.begin(client, apiBaseUrl_ + "/api/v1/device/ota/status")) return false;
  http.addHeader("Authorization", "Bearer " + token);
  http.addHeader("Content-Type", "application/json");
  JsonDocument document;
  document["requestId"] = requestId;
  document["status"] = status;
  document["message"] = message;
  String payload;
  serializeJson(document, payload);
  const int response = http.POST(payload);
  http.end();
  return response >= 200 && response < 300;
}

}  // namespace jkbmsr
