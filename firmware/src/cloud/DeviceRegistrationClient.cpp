#include "DeviceRegistrationClient.h"

#include <ArduinoJson.h>
#if defined(ARDUINO_ARCH_ESP8266)
#include <ESP8266HTTPClient.h>
#else
#include <HTTPClient.h>
#endif
#include <WiFiClientSecure.h>

#include "debug/DebugLog.h"
#include "HardwareProfile.h"
#include "net/PlatformNetwork.h"
#include "net/SecureClient.h"

namespace jkbmsr {

DeviceRegistrationClient::DeviceRegistrationClient(String apiBaseUrl) : apiBaseUrl_(apiBaseUrl) {}

namespace {

bool parseAuthResponse(const String& payload, DeviceRegistrationResult& result) {
  JsonDocument document;
  const DeserializationError error = deserializeJson(document, payload);
  if (error) {
    logError("Device auth response JSON parse failed");
    return false;
  }

  result.token = document["token"] | "";
  result.deviceSecret = document["deviceSecret"] | "";
  // Range matches the full Cloud Service tier spectrum (10s fastest paid
  // tier to 3600s/1hr free tier -- see jkbmsr-api's subscriptionTiers.ts,
  // CLOUD_SERVICE_TIERS[0]). This used to be clamped to 60-300s, then
  // 10-1800s once the free tier still ran a 30-minute interval; when the
  // free tier moved to 1 hour (2026-08-11) this clamp's upper bound wasn't
  // updated to match, so free-tier gateways were silently reporting twice
  // as often as intended. Keep this in sync with the identical clamp in
  // RemoteConfigClient.cpp.
  const uint32_t intervalSeconds = document["config"]["telemetryIntervalSeconds"] | 60;
  result.telemetryIntervalMs = constrain(intervalSeconds, 10U, 3600U) * 1000;
  result.otaEnabled = document["config"]["otaEnabled"] | true;
  result.bmsVendor = document["config"]["bmsVendor"] | "jk";
  result.bmsUartRxPin = document["config"]["bmsUartRxPin"] | kDefaultBmsRxPin;
  result.bmsUartTxPin = document["config"]["bmsUartTxPin"] | kDefaultBmsTxPin;
  result.bmsUartBaudRate = document["config"]["bmsUartBaudRate"] | 115200;
  result.bmsUartCaptureEnabled = document["config"]["bmsUartCaptureEnabled"] | false;
  if (result.token.length() == 0) {
    logError("Device auth response did not include a token");
    return false;
  }

  return true;
}

bool postJson(
    const String& url,
    const JsonDocument& document,
    DeviceRegistrationResult& result) {
  String payload;
  serializeJson(document, payload);
  if (payload.length() == 0 || payload.length() > 1024) {
    logError("Device auth payload size is invalid");
    return false;
  }

  GatewaySecureClient client;
  configureSecureClient(client);

  HTTPClient http;
  if (!http.begin(client, url)) {
    logError("Device auth request could not start");
    return false;
  }

  http.addHeader("Content-Type", "application/json");
  const int status = http.POST(payload);
  const String response = http.getString();
  http.end();

  if (status < 200 || status >= 300) {
    logWarn("Device auth request failed with status " + String(status));
    return false;
  }

  return parseAuthResponse(response, result);
}

}  // namespace

bool DeviceRegistrationClient::registerDevice(
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
    DeviceRegistrationResult& result) {
  if (deviceId.length() == 0 || hardwareId.length() == 0 || hardwareFingerprint.length() == 0 ||
      hardwarePlatform.length() == 0 || targetHardware.length() == 0 || firmwareVersion.length() == 0) {
    logError("Device registration payload is incomplete");
    return false;
  }

  JsonDocument document;
  document["deviceId"] = deviceId;
  document["hardwareId"] = hardwareId;
  document["hardwareFingerprint"] = hardwareFingerprint;
  document["hardwarePlatform"] = hardwarePlatform;
  document["hardwareModel"] = hardwareModel;
  document["targetHardware"] = targetHardware;
  document["boardProfile"] = boardProfile;
  document["firmwareVersion"] = firmwareVersion;
  JsonObject capabilities = document["capabilities"].to<JsonObject>();
  capabilities["wifi"] = true;
  capabilities["uart"] = true;
  capabilities["ble"] = kHasBle;
  capabilities["ota"] = kHasOta;
  // Bind the claim secret at registration so the backend can require it before
  // letting a user account claim this device (anti-spoof).
  if (claimCode.length() > 0) {
    document["claimCode"] = claimCode;
  }
  // Account-bound claim token, provisioned over serial by the signed-in
  // flasher. The backend binds this device to that account and consumes the
  // token on first registration. Sent only while present; cleared once used.
  if (claimToken.length() > 0) {
    document["claimToken"] = claimToken;
  }
  if (!postJson(apiBaseUrl_ + "/api/v1/device/register", document, result)) {
    return false;
  }

  logInfo("Device registered");
  return true;
}

bool DeviceRegistrationClient::loginDevice(
    const String& deviceId,
    const String& deviceSecret,
    const String& hardwareFingerprint,
    const String& hardwarePlatform,
    const String& hardwareModel,
    const String& targetHardware,
    const String& boardProfile,
    const String& firmwareVersion,
    DeviceRegistrationResult& result) {
  if (deviceId.length() == 0 || deviceSecret.length() == 0) {
    logError("Device login payload is incomplete");
    return false;
  }

  JsonDocument document;
  document["deviceId"] = deviceId;
  document["deviceSecret"] = deviceSecret;
  document["hardwareFingerprint"] = hardwareFingerprint;
  document["hardwarePlatform"] = hardwarePlatform;
  document["hardwareModel"] = hardwareModel;
  document["targetHardware"] = targetHardware;
  document["boardProfile"] = boardProfile;
  document["firmwareVersion"] = firmwareVersion;
  JsonObject capabilities = document["capabilities"].to<JsonObject>();
  capabilities["wifi"] = true;
  capabilities["uart"] = true;
  capabilities["ble"] = kHasBle;
  capabilities["ota"] = kHasOta;
  if (!postJson(apiBaseUrl_ + "/api/v1/device/login", document, result)) {
    return false;
  }

  logInfo("Device logged in");
  return true;
}

}  // namespace jkbmsr
