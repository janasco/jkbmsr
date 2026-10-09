#include "TelemetryClient.h"

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

TelemetryClient::TelemetryClient(String apiBaseUrl) : apiBaseUrl_(apiBaseUrl) {}

bool TelemetryClient::sendPayload(const String& token, const String& payload) {
  GatewaySecureClient client;
  configureSecureClient(client);

  HTTPClient http;
  const String url = apiBaseUrl_ + "/v1/telemetry";
  if (!http.begin(client, url)) {
    logError("Telemetry upload request could not start");
    return false;
  }

  http.addHeader("Authorization", "Bearer " + token);
  http.addHeader("Content-Type", "application/json");
  const int status = http.POST(payload);
  http.end();

  authRejected_ = (status == 401);
  if (status < 200 || status >= 300) {
    logWarn("Telemetry upload failed with status " + String(status));
    return false;
  }

  return true;
}

void TelemetryClient::enqueuePending(const String& payload) {
  if (pendingCount_ < kMaxPendingPayloads) {
    pendingPayloads_[pendingCount_] = payload;
    pendingCount_++;
    logWarn("Buffered telemetry reading for retry (" + String(pendingCount_) + " pending)");
    return;
  }
  // Backlog is full — an extended outage, not a blip. Drop the oldest
  // reading to make room rather than growing unbounded or losing the
  // newest (most relevant) sample.
  for (uint8_t index = 1; index < kMaxPendingPayloads; ++index) {
    pendingPayloads_[index - 1] = pendingPayloads_[index];
  }
  pendingPayloads_[kMaxPendingPayloads - 1] = payload;
  logWarn("Telemetry retry backlog full; oldest buffered reading dropped");
}

void TelemetryClient::flushOnePending(const String& token) {
  if (pendingCount_ == 0) {
    return;
  }
  if (sendPayload(token, pendingPayloads_[0])) {
    for (uint8_t index = 1; index < pendingCount_; ++index) {
      pendingPayloads_[index - 1] = pendingPayloads_[index];
    }
    pendingCount_--;
    logInfo("Flushed one buffered telemetry reading (" + String(pendingCount_) + " remaining)");
  }
  // On failure, leave it at the front of the backlog and try again next cycle.
}

bool TelemetryClient::upload(const String& token, const BatteryTelemetry& telemetry) {
  if (token.length() == 0) {
    logWarn("Telemetry upload skipped because device token is missing");
    return false;
  }
  // An invalid sample is still uploaded as a heartbeat: the gateway proves it
  // is online (dashboard last-seen) and reports that the BMS link is down,
  // just without battery readings.
  JsonDocument document;
  document["bmsLinkUp"] = telemetry.valid;
  if (telemetry.valid) {
    document["voltage"] = telemetry.packVoltage;
    document["current"] = telemetry.packCurrent;
    document["soc"] = telemetry.stateOfCharge;
    document["power"] = telemetry.power;
    document["temperature1"] = telemetry.temperature1;
    document["temperature2"] = telemetry.temperature2;
    document["capturedAtMs"] = telemetry.capturedAtMs;
    document["source"] = telemetry.source;
    JsonObject bms = document["bms"].to<JsonObject>();
    bms["mosfetTemperature"] = telemetry.mosfetTemperature;
    bms["minCellVoltage"] = telemetry.minCellVoltage;
    bms["maxCellVoltage"] = telemetry.maxCellVoltage;
    bms["avgCellVoltage"] = telemetry.avgCellVoltage;
    bms["deltaCellVoltage"] = telemetry.deltaCellVoltage;
    bms["minVoltageCell"] = telemetry.minVoltageCell;
    bms["maxVoltageCell"] = telemetry.maxVoltageCell;
    bms["temperatureSensorCount"] = telemetry.temperatureSensorCount;
    bms["cycleCount"] = telemetry.cycleCount;
    bms["cycleCapacityAh"] = telemetry.cycleCapacityAh;
    bms["fullCapacityAh"] = telemetry.fullCapacityAh;
    bms["remainingCapacityAh"] = telemetry.remainingCapacityAh;
    if (telemetry.stateOfHealth != 0xFF) {
      bms["stateOfHealth"] = telemetry.stateOfHealth;
    }
    bms["errorsBitmask"] = telemetry.errorsBitmask;
    bms["charging"] = telemetry.chargingEnabled;
    bms["discharging"] = telemetry.dischargingEnabled;
    bms["balancing"] = telemetry.balancingActive;
    bms["balancingCurrent"] = telemetry.balancingCurrent;
    bms["softwareVersion"] = telemetry.bmsSoftwareVersion;
    bms["protocolVersion"] = telemetry.protocolVersion;
  }
  JsonObject parser = document["parser"].to<JsonObject>();
  parser["lastFrameAtMs"] = telemetry.parserLastFrameAtMs;
  parser["parseErrors"] = telemetry.parserParseErrors;
  parser["bytesReceived"] = telemetry.parserBytesReceived;
  parser["staleBytes"] = telemetry.parserStaleBytes;
  parser["rawCaptureEnabled"] = telemetry.parserRawCaptureEnabled;
  JsonObject ota = document["ota"].to<JsonObject>();
  ota["lastCheckAtMs"] = telemetry.otaLastCheckAtMs;
  ota["lastCheckSucceeded"] = telemetry.otaLastCheckSucceeded;
  ota["updateAvailable"] = telemetry.otaUpdateAvailable;
  ota["updateApplied"] = telemetry.otaUpdateApplied;
  ota["offeredVersion"] = telemetry.otaOfferedVersion;
  ota["lastResult"] = telemetry.otaLastResult;
  JsonObject ble = document["ble"].to<JsonObject>();
  ble["state"] = telemetry.bleState;
  ble["address"] = telemetry.bleAddress;
  ble["advertisedName"] = telemetry.bleAdvertisedName;
  ble["hardwareVersion"] = telemetry.bleHardwareVersion;
  ble["softwareVersion"] = telemetry.bleSoftwareVersion;
  ble["rssi"] = telemetry.bleRssi;
  ble["addressType"] = telemetry.bleAddressType;
  ble["framesDecoded"] = telemetry.bleFramesDecoded;
  ble["checksumErrors"] = telemetry.bleChecksumErrors;
  ble["lastFrameAtMs"] = telemetry.bleLastFrameAtMs;
  ble["lastScanAtMs"] = telemetry.bleLastScanAtMs;
  ble["lastConnectedAtMs"] = telemetry.bleLastConnectedAtMs;
  ble["lastError"] = telemetry.bleLastError;
  ble["readOnly"] = telemetry.bleReadOnly;
  JsonArray candidates = ble["candidates"].to<JsonArray>();
  for (uint8_t index = 0; index < telemetry.bleCandidateCount; ++index) {
    JsonObject candidate = candidates.add<JsonObject>();
    candidate["address"] = telemetry.bleCandidateAddresses[index];
    candidate["name"] = telemetry.bleCandidateNames[index];
    candidate["rssi"] = telemetry.bleCandidateRssi[index];
    candidate["addressType"] = telemetry.bleCandidateAddressTypes[index];
  }
  if (telemetry.valid) {
    JsonArray cells = document["cellVoltages"].to<JsonArray>();
    for (uint8_t index = 0; index < telemetry.cellCount; ++index) {
      JsonObject cell = cells.add<JsonObject>();
      cell["cell"] = index + 1;
      cell["voltage"] = telemetry.cellVoltages[index];
    }
  }

  String payload;
  serializeJson(document, payload);
  // A 32-cell frame with the extended BMS block is ~2.5 KB; the cloud accepts
  // up to 8 KB.
  if (payload.length() == 0 || payload.length() > 4096) {
    logError("Telemetry upload skipped because JSON payload size is invalid");
    return false;
  }

  // Drain at most one backlogged reading per cycle before sending the
  // current one — self-throttled so a reconnect after an outage doesn't
  // burst the whole backlog at once, and bounded to one extra request per
  // telemetry interval either way.
  flushOnePending(token);

  if (sendPayload(token, payload)) {
    logInfo(telemetry.valid ? "Telemetry uploaded" : "Heartbeat uploaded (BMS link down)");
    return true;
  }

  // A heartbeat-only sample (BMS link down, no real readings) isn't worth
  // buffering for retry — there is no battery data to recover, and
  // re-sending a stale "link down" heartbeat later provides no value.
  if (telemetry.valid) {
    enqueuePending(payload);
  }
  return false;
}

}  // namespace jkbmsr
