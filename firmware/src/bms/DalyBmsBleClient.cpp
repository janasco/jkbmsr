#include "DalyBmsBleClient.h"

#include <NimBLEDevice.h>

#include "bms/DalyD2Decoder.h"
#include "debug/DebugLog.h"

namespace jkbmsr {

namespace {

constexpr uint16_t kServiceUuid = 0xFFF0;
constexpr uint16_t kNotifyCharacteristicUuid = 0xFFF1;
constexpr uint16_t kControlCharacteristicUuid = 0xFFF2;

DalyBmsBleClient* g_activeClient = nullptr;

void onNotify(NimBLERemoteCharacteristic* /*characteristic*/, uint8_t* data, size_t length,
              bool /*isNotify*/) {
  if (g_activeClient != nullptr) {
    g_activeClient->handleNotification(data, length);
  }
}

}  // namespace

void DalyBmsBleClient::begin(const String& address) {
  if (enabled_ && configuredAddress_ == address) {
    return;
  }
  stop();
  configuredAddress_ = address;
  targetAddress_ = address;
  targetAddressType_ = BLE_ADDR_PUBLIC;
  enabled_ = true;
  status_.enabled = enabled_;
  status_.state = targetAddress_.length() > 0 ? "connecting" : "scanning";
  status_.address = targetAddress_;
  status_.lastError = "";
  if (!stackInitialized_) {
    NimBLEDevice::init("");
    stackInitialized_ = true;
  }
  g_activeClient = this;
  logInfo("Daly-BMS BLE client targeting " + targetAddress_);
}

void DalyBmsBleClient::stop() {
  enabled_ = false;
  status_.enabled = false;
  status_.connected = false;
  status_.state = "disabled";
  assemblyLength_ = 0;
  if (client_ != nullptr) {
    auto* client = static_cast<NimBLEClient*>(client_);
    if (client->isConnected()) {
      client->disconnect();
    }
    NimBLEDevice::deleteClient(client);
    client_ = nullptr;
  }
}

void DalyBmsBleClient::loop() {
  if (!enabled_) {
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client != nullptr && client->isConnected()) {
    status_.connected = true;
    return;
  }

  status_.connected = false;
  if (status_.state == "connected") {
    status_.state = "disconnected";
  }
  connectIfDue();
}

void DalyBmsBleClient::connectIfDue() {
  if (lastConnectAttemptMs_ != 0 && millis() - lastConnectAttemptMs_ < kReconnectIntervalMs) {
    return;
  }
  lastConnectAttemptMs_ = millis();
  assemblyLength_ = 0;

  if (targetAddress_.length() == 0 && !discoverTarget()) {
    status_.state = "not_found";
    status_.lastError = "No compatible Daly BMS advertisement found";
    logWarn("No Daly BMS BLE advertisement found; retrying in 30s");
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client == nullptr) {
    client = NimBLEDevice::createClient();
    client->setConnectTimeout(5);
    client_ = client;
  }

  logInfo("Connecting to Daly BMS over BLE");
  status_.state = "connecting";
  if (!client->connect(NimBLEAddress(targetAddress_.c_str(), targetAddressType_))) {
    status_.state = "connection_failed";
    status_.lastError = "BLE connection failed";
    if (configuredAddress_.length() > 0) {
      targetAddressType_ = targetAddressType_ == BLE_ADDR_PUBLIC ? BLE_ADDR_RANDOM : BLE_ADDR_PUBLIC;
      status_.addressType = targetAddressType_;
    }
    logWarn("Daly BMS BLE connection failed; retrying in 30s");
    return;
  }

  NimBLERemoteService* service = client->getService(NimBLEUUID(kServiceUuid));
  NimBLERemoteCharacteristic* notifyChar =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kNotifyCharacteristicUuid)) : nullptr;
  NimBLERemoteCharacteristic* controlChar =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kControlCharacteristicUuid)) : nullptr;
  if (notifyChar == nullptr || controlChar == nullptr || !notifyChar->canNotify() ||
      !notifyChar->subscribe(true, onNotify)) {
    logWarn("Daly BMS BLE service 0xFFF0/0xFFF1/0xFFF2 unavailable; disconnecting");
    status_.state = "service_unavailable";
    status_.lastError = "FFF0/FFF1/FFF2 service unavailable";
    client->disconnect();
    return;
  }

  logInfo("Daly BMS BLE connected");
  status_.connected = true;
  status_.state = "connected";
  status_.lastError = "";
  status_.lastConnectedAtMs = millis();
  lastRequestMs_ = millis();
  sendStatusRequest();
}

bool DalyBmsBleClient::discoverTarget() {
  logInfo("Scanning for Daly BMS Bluetooth advertisements");
  status_.state = "scanning";
  status_.lastScanAtMs = millis();
  NimBLEScan* scan = NimBLEDevice::getScan();
  scan->setActiveScan(true);
  // NimBLE-Arduino 2.x (only env:esp32-c6-4mb) made start() return a bool
  // and getDevice() return a pointer instead of a value; 1.x (every other
  // target) keeps the old value-returning API. getResults(duration,
  // isContinue) is 2.x's closest equivalent to 1.x's start(duration,
  // isContinue).
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
  NimBLEScanResults results = scan->getResults(5, false);
#else
  NimBLEScanResults results = scan->start(5, false);
#endif
  int bestRssi = -128;
  String bestAddress;
  String bestName;
  uint8_t bestAddressType = BLE_ADDR_PUBLIC;
  status_.candidateCount = 0;

  for (int i = 0; i < results.getCount(); ++i) {
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
    const NimBLEAdvertisedDevice& device = *results.getDevice(i);
#else
    NimBLEAdvertisedDevice device = results.getDevice(i);
#endif
    const bool dalyService = device.haveServiceUUID() &&
                             device.isAdvertisingService(NimBLEUUID(kServiceUuid));
    const String name = device.haveName() ? String(device.getName().c_str()) : String();
    const bool dalyName = name.startsWith("DL");
    if (!(dalyService || dalyName)) {
      continue;
    }
    if (status_.candidateCount < kMaxBmsBleCandidates) {
      BmsBleCandidate& candidate = status_.candidates[status_.candidateCount++];
      candidate.address = device.getAddress().toString().c_str();
      candidate.name = name;
      candidate.rssi = device.getRSSI();
      candidate.addressType = device.getAddress().getType();
    }
    if (device.getRSSI() > bestRssi) {
      bestRssi = device.getRSSI();
      bestAddress = device.getAddress().toString().c_str();
      bestAddressType = device.getAddress().getType();
      bestName = name;
    }
  }
  scan->clearResults();
  if (bestAddress.length() == 0) {
    return false;
  }
  targetAddress_ = bestAddress;
  targetAddressType_ = bestAddressType;
  status_.address = targetAddress_;
  status_.addressType = targetAddressType_;
  status_.advertisedName = bestName;
  status_.rssi = bestRssi;
  logInfo("Discovered Daly BMS BLE device " + targetAddress_ + " (RSSI " + String(bestRssi) + ")");
  return true;
}

bool DalyBmsBleClient::sendStatusRequest() {
  auto* client = static_cast<NimBLEClient*>(client_);
  if (client == nullptr || !client->isConnected()) {
    return false;
  }
  NimBLERemoteService* service = client->getService(NimBLEUUID(kServiceUuid));
  NimBLERemoteCharacteristic* controlChar =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kControlCharacteristicUuid)) : nullptr;
  if (controlChar == nullptr) {
    return false;
  }
  uint8_t frame[8];
  DalyD2Decoder::buildStatusRequest(frame);
  return controlChar->writeValue(frame, sizeof(frame), false);
}

void DalyBmsBleClient::handleNotification(const uint8_t* data, size_t length) {
  if (data == nullptr || length == 0) {
    return;
  }
  if (assemblyLength_ + length > kAssemblyBufferSize) {
    assemblyLength_ = 0;
  }
  // A new frame header restarts assembly.
  if (length >= 2 && data[0] == 0xD2 && data[1] == 0x03 && assemblyLength_ > 0) {
    assemblyLength_ = 0;
  }
  memcpy(assemblyBuffer_ + assemblyLength_, data, length);
  assemblyLength_ += length;

  if (assemblyLength_ >= kAssemblyTargetSize) {
    processFrame(assemblyBuffer_, kAssemblyTargetSize);
    assemblyLength_ = 0;
  }
}

void DalyBmsBleClient::processFrame(const uint8_t* frame, size_t length) {
  BatteryTelemetry decoded;
  if (!DalyD2Decoder::parseStatusFrame(frame, length, decoded)) {
    status_.checksumErrors += 1;
    return;
  }
  decoded.capturedAtMs = millis();
  latest_ = decoded;
  status_.framesDecoded += 1;
  status_.lastFrameAtMs = decoded.capturedAtMs;
}

bool DalyBmsBleClient::poll(BatteryTelemetry& telemetry) {
  if (!enabled_) {
    return false;
  }
  if (millis() - lastRequestMs_ >= kRequestIntervalMs) {
    lastRequestMs_ = millis();
    sendStatusRequest();
  }
  if (!latest_.valid || millis() - latest_.capturedAtMs > kSampleFreshMs) {
    return false;
  }
  telemetry = latest_;
  return true;
}

BmsBleStatus DalyBmsBleClient::status() const {
  return status_;
}

}  // namespace jkbmsr
