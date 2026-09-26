#include "KsBmsBleClient.h"

#include <NimBLEDevice.h>

#include "bms/KsBmsDecoder.h"
#include "debug/DebugLog.h"

namespace jkbmsr {

namespace {

constexpr uint16_t kServiceUuid = 0xFF00;
constexpr uint16_t kNotifyCharacteristicUuid = 0xFF01;
constexpr uint16_t kControlCharacteristicUuid = 0xFF02;
constexpr uint8_t kFrameStart = 0x7B;

KsBmsBleClient* g_activeClient = nullptr;

void onNotify(NimBLERemoteCharacteristic* /*characteristic*/, uint8_t* data, size_t length,
              bool /*isNotify*/) {
  if (g_activeClient != nullptr) {
    g_activeClient->handleNotification(data, length);
  }
}

}  // namespace

void KsBmsBleClient::begin(const String& address) {
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
  logInfo("KS48100 BMS BLE client targeting " + targetAddress_);
}

void KsBmsBleClient::stop() {
  enabled_ = false;
  status_.enabled = false;
  status_.connected = false;
  status_.state = "disabled";
  assemblyLength_ = 0;
  frameValidatedSinceConnect_ = false;
  statusValid_ = false;
  excludedAddress_ = "";
  if (client_ != nullptr) {
    auto* client = static_cast<NimBLEClient*>(client_);
    if (client->isConnected()) {
      client->disconnect();
    }
    NimBLEDevice::deleteClient(client);
    client_ = nullptr;
  }
}

void KsBmsBleClient::loop() {
  if (!enabled_) {
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client != nullptr && client->isConnected()) {
    status_.connected = true;
    if (!frameValidatedSinceConnect_ && millis() - connectedAtMs_ > kFrameValidationTimeoutMs) {
      logWarn("KS48100 BMS BLE connected but no valid frame after " +
              String(kFrameValidationTimeoutMs / 1000) + "s; likely wrong device, disconnecting");
      status_.lastError = "Connected but got no valid data — likely a different BLE device sharing this UUID";
      client->disconnect();
      if (configuredAddress_.length() == 0) {
        excludedAddress_ = targetAddress_;
        targetAddress_ = "";
      }
      lastConnectAttemptMs_ = 0;
    }
    return;
  }

  status_.connected = false;
  if (status_.state == "connected") {
    status_.state = "disconnected";
  }
  connectIfDue();
}

void KsBmsBleClient::connectIfDue() {
  if (lastConnectAttemptMs_ != 0 && millis() - lastConnectAttemptMs_ < kReconnectIntervalMs) {
    return;
  }
  lastConnectAttemptMs_ = millis();
  assemblyLength_ = 0;

  if (targetAddress_.length() == 0 && !discoverTarget()) {
    status_.state = "not_found";
    status_.lastError = "No compatible KS48100 BMS advertisement found";
    logWarn("No KS48100 BMS BLE advertisement found; retrying in 30s");
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client == nullptr) {
    client = NimBLEDevice::createClient();
    client->setConnectTimeout(5);
    client_ = client;
  }

  logInfo("Connecting to KS48100 BMS over BLE");
  status_.state = "connecting";
  if (!client->connect(NimBLEAddress(targetAddress_.c_str(), targetAddressType_))) {
    status_.state = "connection_failed";
    status_.lastError = "BLE connection failed";
    if (configuredAddress_.length() > 0) {
      targetAddressType_ = targetAddressType_ == BLE_ADDR_PUBLIC ? BLE_ADDR_RANDOM : BLE_ADDR_PUBLIC;
      status_.addressType = targetAddressType_;
    }
    logWarn("KS48100 BMS BLE connection failed; retrying in 30s");
    return;
  }

  NimBLERemoteService* service = client->getService(NimBLEUUID(kServiceUuid));
  NimBLERemoteCharacteristic* notifyChar =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kNotifyCharacteristicUuid)) : nullptr;
  NimBLERemoteCharacteristic* controlChar =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kControlCharacteristicUuid)) : nullptr;
  if (notifyChar == nullptr || controlChar == nullptr || !notifyChar->canNotify() ||
      !notifyChar->subscribe(true, onNotify)) {
    logWarn("KS48100 BMS BLE service 0xFF00/0xFF01/0xFF02 unavailable; disconnecting");
    status_.state = "service_unavailable";
    status_.lastError = "FF00/FF01/FF02 service unavailable";
    client->disconnect();
    return;
  }

  logInfo("KS48100 BMS BLE connected");
  status_.connected = true;
  status_.state = "connected";
  status_.lastError = "";
  status_.lastConnectedAtMs = millis();
  connectedAtMs_ = millis();
  frameValidatedSinceConnect_ = false;
  statusValid_ = false;
  latest_.valid = false;
  requestQueue_[0] = KsBmsDecoder::kFrameTypeStatus;
  requestQueue_[1] = KsBmsDecoder::kFrameTypeCellVoltages;
  requestPos_ = 0;
  lastRequestMs_ = millis();
  sendNextRequest();
}

bool KsBmsBleClient::discoverTarget() {
  logInfo("Scanning for KS48100 BMS Bluetooth advertisements");
  status_.state = "scanning";
  status_.lastScanAtMs = millis();
  NimBLEScan* scan = NimBLEDevice::getScan();
  scan->setActiveScan(true);
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
    const bool ksService = device.haveServiceUUID() && device.isAdvertisingService(NimBLEUUID(kServiceUuid));
    if (!ksService) {
      continue;
    }
    const String name = device.haveName() ? String(device.getName().c_str()) : String();
    const String address = String(device.getAddress().toString().c_str());
    if (status_.candidateCount < kMaxBmsBleCandidates) {
      BmsBleCandidate& candidate = status_.candidates[status_.candidateCount++];
      candidate.address = address;
      candidate.name = name;
      candidate.rssi = device.getRSSI();
      candidate.addressType = device.getAddress().getType();
    }
    if (excludedAddress_.length() > 0 && address == excludedAddress_) {
      continue;
    }
    const String lowerName = name;
    const bool nameHintsKs = lowerName.length() > 0 &&
                             (lowerName.startsWith("ks") || lowerName.indexOf("ks48100") >= 0);
    const int effectiveRssi = nameHintsKs ? (device.getRSSI() + 256) : device.getRSSI();
    if (effectiveRssi > bestRssi) {
      bestRssi = effectiveRssi;
      bestAddress = address;
      bestAddressType = device.getAddress().getType();
      bestName = name;
    }
  }
  scan->clearResults();
  excludedAddress_ = "";
  if (bestAddress.length() == 0) {
    return false;
  }
  targetAddress_ = bestAddress;
  targetAddressType_ = bestAddressType;
  status_.address = targetAddress_;
  status_.addressType = targetAddressType_;
  status_.advertisedName = bestName;
  status_.rssi = bestRssi > 0 ? bestRssi - 256 : bestRssi;
  logInfo("Discovered KS48100 BMS BLE device " + targetAddress_ + " (RSSI " + String(status_.rssi) + ")");
  return true;
}

bool KsBmsBleClient::sendNextRequest() {
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
  uint8_t frame[KsBmsDecoder::kRequestFrameSize];
  KsBmsDecoder::buildCommandFrame(frame, requestQueue_[requestPos_]);
  requestPos_ = static_cast<uint8_t>((requestPos_ + 1) % kMaxRequests);
  return controlChar->writeValue(frame, sizeof(frame), false);
}

void KsBmsBleClient::handleNotification(const uint8_t* data, size_t length) {
  if (data == nullptr || length == 0) {
    return;
  }
  // Frames are atomic per upstream (no reassembly), but a definitive 0x7B
  // preamble resets the accumulator in case a chunk arrived split.
  if (data[0] == kFrameStart && assemblyLength_ > 0) {
    assemblyLength_ = 0;
  }
  const size_t remaining = kAssemblyBufferSize - assemblyLength_;
  if (length > remaining) {
    assemblyLength_ = 0;
    return;
  }
  memcpy(assemblyBuffer_ + assemblyLength_, data, length);
  assemblyLength_ += length;
  if (KsBmsDecoder::isCompleteFrame(assemblyBuffer_, assemblyLength_)) {
    processFrame(assemblyBuffer_, assemblyLength_);
    assemblyLength_ = 0;
  }
}

void KsBmsBleClient::processFrame(const uint8_t* frame, size_t length) {
  const uint8_t type = frame[1];
  if (type == KsBmsDecoder::kFrameTypeStatus || type == KsBmsDecoder::kFrameTypeStatusType2) {
    if (!KsBmsDecoder::parseStatusFrame(frame, length, latest_)) {
      status_.checksumErrors += 1;
      return;
    }
    statusValid_ = true;
    latest_.valid = true;
  } else if (type == KsBmsDecoder::kFrameTypeCellVoltages) {
    if (!statusValid_) {
      return;
    }
    if (!KsBmsDecoder::parseCellVoltagesFrame(frame, length, latest_)) {
      status_.checksumErrors += 1;
      return;
    }
    latest_.valid = true;
  } else {
    status_.checksumErrors += 1;
    return;
  }
  latest_.capturedAtMs = millis();
  frameValidatedSinceConnect_ = true;
  status_.framesDecoded += 1;
  status_.lastFrameAtMs = latest_.capturedAtMs;
}

bool KsBmsBleClient::poll(BatteryTelemetry& telemetry) {
  if (!enabled_) {
    return false;
  }
  if (millis() - lastRequestMs_ >= kRequestIntervalMs) {
    lastRequestMs_ = millis();
    sendNextRequest();
  }
  if (!latest_.valid || millis() - latest_.capturedAtMs > kSampleFreshMs) {
    return false;
  }
  telemetry = latest_;
  return true;
}

BmsBleStatus KsBmsBleClient::status() const {
  return status_;
}

}  // namespace jkbmsr