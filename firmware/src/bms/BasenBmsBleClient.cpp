#include "BasenBmsBleClient.h"

#include <NimBLEDevice.h>

#include "bms/BasenBmsDecoder.h"
#include "debug/DebugLog.h"

namespace jkbmsr {

namespace {

constexpr uint16_t kServiceUuid = 0xFA00;
constexpr uint16_t kNotifyCharacteristicUuid = 0xFA01;
constexpr uint16_t kControlCharacteristicUuid = 0xFA02;
constexpr uint8_t kFrameStartA = 0x3A;
constexpr uint8_t kFrameStartB = 0x3B;

BasenBmsBleClient* g_activeClient = nullptr;

void onNotify(NimBLERemoteCharacteristic* /*characteristic*/, uint8_t* data, size_t length,
              bool /*isNotify*/) {
  if (g_activeClient != nullptr) {
    g_activeClient->handleNotification(data, length);
  }
}

}  // namespace

void BasenBmsBleClient::begin(const String& address) {
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
  logInfo("Basen BMS BLE client targeting " + targetAddress_);
}

void BasenBmsBleClient::stop() {
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

void BasenBmsBleClient::loop() {
  if (!enabled_) {
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client != nullptr && client->isConnected()) {
    status_.connected = true;
    if (!frameValidatedSinceConnect_ && millis() - connectedAtMs_ > kFrameValidationTimeoutMs) {
      logWarn("Basen BMS BLE connected but no valid frame after " +
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

void BasenBmsBleClient::connectIfDue() {
  if (lastConnectAttemptMs_ != 0 && millis() - lastConnectAttemptMs_ < kReconnectIntervalMs) {
    return;
  }
  lastConnectAttemptMs_ = millis();
  assemblyLength_ = 0;

  if (targetAddress_.length() == 0 && !discoverTarget()) {
    status_.state = "not_found";
    status_.lastError = "No compatible Basen BMS advertisement found";
    logWarn("No Basen BMS BLE advertisement found; retrying in 30s");
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client == nullptr) {
    client = NimBLEDevice::createClient();
    client->setConnectTimeout(5);
    client_ = client;
  }

  logInfo("Connecting to Basen BMS over BLE");
  status_.state = "connecting";
  if (!client->connect(NimBLEAddress(targetAddress_.c_str(), targetAddressType_))) {
    status_.state = "connection_failed";
    status_.lastError = "BLE connection failed";
    if (configuredAddress_.length() > 0) {
      targetAddressType_ = targetAddressType_ == BLE_ADDR_PUBLIC ? BLE_ADDR_RANDOM : BLE_ADDR_PUBLIC;
      status_.addressType = targetAddressType_;
    }
    logWarn("Basen BMS BLE connection failed; retrying in 30s");
    return;
  }

  NimBLERemoteService* service = client->getService(NimBLEUUID(kServiceUuid));
  NimBLERemoteCharacteristic* notifyChar =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kNotifyCharacteristicUuid)) : nullptr;
  NimBLERemoteCharacteristic* controlChar =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kControlCharacteristicUuid)) : nullptr;
  if (notifyChar == nullptr || controlChar == nullptr || !notifyChar->canNotify() ||
      !notifyChar->subscribe(true, onNotify)) {
    logWarn("Basen BMS BLE service 0xFA00/0xFA01/0xFA02 unavailable; disconnecting");
    status_.state = "service_unavailable";
    status_.lastError = "FA00/FA01/FA02 service unavailable";
    client->disconnect();
    return;
  }

  logInfo("Basen BMS BLE connected");
  status_.connected = true;
  status_.state = "connected";
  status_.lastError = "";
  status_.lastConnectedAtMs = millis();
  connectedAtMs_ = millis();
  frameValidatedSinceConnect_ = false;
  statusValid_ = false;
  latest_.valid = false;
  requestQueue_[0] = BasenBmsDecoder::kFrameTypeStatus;
  requestQueue_[1] = BasenBmsDecoder::kFrameTypeGeneralInfo;
  requestQueue_[2] = BasenBmsDecoder::kFrameTypeCellVoltages1_12;
  requestQueue_[3] = BasenBmsDecoder::kFrameTypeCellVoltages13_24;
  requestPos_ = 0;
  lastRequestMs_ = millis();
  sendNextRequest();
}

bool BasenBmsBleClient::discoverTarget() {
  logInfo("Scanning for Basen BMS Bluetooth advertisements");
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
    const bool basenService = device.haveServiceUUID() && device.isAdvertisingService(NimBLEUUID(kServiceUuid));
    if (!basenService) {
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
    const bool nameHintsBasen = name.length() > 0 && name.indexOf("basen") >= 0;
    const int effectiveRssi = nameHintsBasen ? (device.getRSSI() + 256) : device.getRSSI();
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
  logInfo("Discovered Basen BMS BLE device " + targetAddress_ + " (RSSI " + String(status_.rssi) + ")");
  return true;
}

bool BasenBmsBleClient::sendNextRequest() {
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
  uint8_t frame[BasenBmsDecoder::kMaxRequestFrameSize];
  BasenBmsDecoder::buildRequestFrame(frame, requestQueue_[requestPos_]);
  requestPos_ = static_cast<uint8_t>((requestPos_ + 1) % kMaxRequests);
  return controlChar->writeValue(frame, sizeof(frame), false);
}

void BasenBmsBleClient::handleNotification(const uint8_t* data, size_t length) {
  if (data == nullptr || length == 0) {
    return;
  }
  // A new frame preamble restarts assembly.
  if ((data[0] == kFrameStartA || data[0] == kFrameStartB) && assemblyLength_ > 0) {
    assemblyLength_ = 0;
  }
  if (assemblyLength_ + length > kAssemblyBufferSize) {
    assemblyLength_ = 0;
  }
  memcpy(assemblyBuffer_ + assemblyLength_, data, length);
  assemblyLength_ += length;

  const size_t frameLen = BasenBmsDecoder::frameCompleteLength(assemblyBuffer_, assemblyLength_);
  if (frameLen > 0) {
    processFrame(assemblyBuffer_, frameLen);
    // A single notification can hold a full frame plus the start of the next
    // one; drop only the consumed bytes.
    memmove(assemblyBuffer_, assemblyBuffer_ + frameLen, assemblyLength_ - frameLen);
    assemblyLength_ -= frameLen;
  }
}

void BasenBmsBleClient::processFrame(const uint8_t* frame, size_t length) {
  const uint8_t type = frame[2];
  if (type == BasenBmsDecoder::kFrameTypeStatus) {
    if (!BasenBmsDecoder::parseStatusFrame(frame, length, latest_)) {
      status_.checksumErrors += 1;
      return;
    }
    statusValid_ = true;
    latest_.valid = true;
  } else if (type == BasenBmsDecoder::kFrameTypeCellVoltages1_12 ||
             type == BasenBmsDecoder::kFrameTypeCellVoltages13_24) {
    if (!statusValid_) {
      return;
    }
    if (!BasenBmsDecoder::parseCellChunkFrame(frame, length, latest_)) {
      status_.checksumErrors += 1;
      return;
    }
    latest_.valid = true;
  } else if (type == BasenBmsDecoder::kFrameTypeGeneralInfo) {
    if (!BasenBmsDecoder::parseGeneralInfoFrame(frame, length, latest_)) {
      status_.checksumErrors += 1;
      return;
    }
    if (statusValid_) {
      latest_.valid = true;
    }
  } else {
    status_.checksumErrors += 1;
    return;
  }
  latest_.capturedAtMs = millis();
  frameValidatedSinceConnect_ = true;
  status_.framesDecoded += 1;
  status_.lastFrameAtMs = latest_.capturedAtMs;
}

bool BasenBmsBleClient::poll(BatteryTelemetry& telemetry) {
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

BmsBleStatus BasenBmsBleClient::status() const {
  return status_;
}

}  // namespace jkbmsr