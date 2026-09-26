#include "AntBmsBleClient.h"

#include <NimBLEDevice.h>

#include "bms/AntBmsDecoder.h"
#include "debug/DebugLog.h"

namespace jkbmsr {

namespace {

constexpr uint16_t kServiceUuid = 0xFFE0;
constexpr uint16_t kCharacteristicUuid = 0xFFE1;  // write + notify in one
constexpr uint8_t kFrameStart1 = 0x7E;

AntBmsBleClient* g_activeClient = nullptr;

void onNotify(NimBLERemoteCharacteristic* /*characteristic*/, uint8_t* data, size_t length,
              bool /*isNotify*/) {
  if (g_activeClient != nullptr) {
    g_activeClient->handleNotification(data, length);
  }
}

}  // namespace

void AntBmsBleClient::begin(const String& address) {
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
  logInfo("ANT BMS BLE client targeting " + targetAddress_);
}

void AntBmsBleClient::stop() {
  enabled_ = false;
  status_.enabled = false;
  status_.connected = false;
  status_.state = "disabled";
  assemblyLength_ = 0;
  frameValidatedSinceConnect_ = false;
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

void AntBmsBleClient::loop() {
  if (!enabled_) {
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client != nullptr && client->isConnected()) {
    status_.connected = true;
    if (!frameValidatedSinceConnect_ && millis() - connectedAtMs_ > kFrameValidationTimeoutMs) {
      // Service 0xFFE0 is shared with JK/Topband/Lolan, so a connected-but-
      // never-decoding link is most likely a wrong vendor. See SeplosBmsBleClient.
      logWarn("ANT BMS BLE connected but no valid frame after " +
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

void AntBmsBleClient::connectIfDue() {
  if (lastConnectAttemptMs_ != 0 && millis() - lastConnectAttemptMs_ < kReconnectIntervalMs) {
    return;
  }
  lastConnectAttemptMs_ = millis();
  assemblyLength_ = 0;

  if (targetAddress_.length() == 0 && !discoverTarget()) {
    status_.state = "not_found";
    status_.lastError = "No compatible ANT BMS advertisement found";
    logWarn("No ANT BMS BLE advertisement found; retrying in 30s");
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client == nullptr) {
    client = NimBLEDevice::createClient();
    client->setConnectTimeout(5);
    client_ = client;
  }

  logInfo("Connecting to ANT BMS over BLE");
  status_.state = "connecting";
  if (!client->connect(NimBLEAddress(targetAddress_.c_str(), targetAddressType_))) {
    status_.state = "connection_failed";
    status_.lastError = "BLE connection failed";
    if (configuredAddress_.length() > 0) {
      targetAddressType_ = targetAddressType_ == BLE_ADDR_PUBLIC ? BLE_ADDR_RANDOM : BLE_ADDR_PUBLIC;
      status_.addressType = targetAddressType_;
    }
    logWarn("ANT BMS BLE connection failed; retrying in 30s");
    return;
  }

  NimBLERemoteService* service = client->getService(NimBLEUUID(kServiceUuid));
  NimBLERemoteCharacteristic* characteristic =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kCharacteristicUuid)) : nullptr;
  if (characteristic == nullptr || !characteristic->canNotify() || !characteristic->subscribe(true, onNotify)) {
    logWarn("ANT BMS BLE service 0xFFE0/0xFFE1 unavailable; disconnecting");
    status_.state = "service_unavailable";
    status_.lastError = "FFE0/FFE1 service unavailable";
    client->disconnect();
    return;
  }

  logInfo("ANT BMS BLE connected");
  status_.connected = true;
  status_.state = "connected";
  status_.lastError = "";
  status_.lastConnectedAtMs = millis();
  connectedAtMs_ = millis();
  frameValidatedSinceConnect_ = false;
  lastRequestMs_ = millis();
  sendStatusRequest();
}

bool AntBmsBleClient::discoverTarget() {
  logInfo("Scanning for ANT BMS Bluetooth advertisements");
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
    const bool antService = device.haveServiceUUID() && device.isAdvertisingService(NimBLEUUID(kServiceUuid));
    if (!antService) {
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
    // 0xFFE0 is shared with JK/Topband/Lolan; an advertised "ant*" name is the
    // reliable signal (the app brands on the same heuristic). Fall back to the
    // strongest service advertiser when no unit advertises a name.
    const String lowerName = name;
    const bool nameHintsAnt =
        lowerName.length() > 0 && (lowerName.equalsIgnoreCase("ant") || lowerName.startsWith("ant") ||
                                   lowerName.indexOf("antbms") >= 0);
    const int effectiveRssi = nameHintsAnt ? (device.getRSSI() + 256) : device.getRSSI();
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
  logInfo("Discovered ANT BMS BLE device " + targetAddress_ + " (RSSI " + String(status_.rssi) + ")");
  return true;
}

bool AntBmsBleClient::sendStatusRequest() {
  auto* client = static_cast<NimBLEClient*>(client_);
  if (client == nullptr || !client->isConnected()) {
    return false;
  }
  NimBLERemoteService* service = client->getService(NimBLEUUID(kServiceUuid));
  NimBLERemoteCharacteristic* characteristic =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kCharacteristicUuid)) : nullptr;
  if (characteristic == nullptr) {
    return false;
  }
  uint8_t frame[AntBmsDecoder::kRequestFrameSize];
  AntBmsDecoder::buildStatusRequest(frame);
  return characteristic->writeValue(frame, sizeof(frame), false);
}

void AntBmsBleClient::handleNotification(const uint8_t* data, size_t length) {
  if (data == nullptr || length == 0) {
    return;
  }
  // A new frame preamble restarts assembly.
  if (data[0] == kFrameStart1) {
    assemblyLength_ = 0;
  }
  if (assemblyLength_ + length > kAssemblyBufferSize) {
    assemblyLength_ = 0;
  }
  memcpy(assemblyBuffer_ + assemblyLength_, data, length);
  assemblyLength_ += length;

  // Variable-length frame: declared by byte 5. 7E A1 [fn] [addrLo addrHi] [len]
  // [payload...] [crc lo hi] AA 55 → frameLen = 6 + len + 4.
  if (assemblyLength_ >= 7) {
    const size_t frameLen = 6 + static_cast<size_t>(assemblyBuffer_[5]) + 4;
    if (frameLen > kAssemblyBufferSize) {
      assemblyLength_ = 0;
      return;
    }
    if (assemblyLength_ >= frameLen) {
      processFrame(assemblyBuffer_, frameLen);
      assemblyLength_ = 0;
    }
  }
}

void AntBmsBleClient::processFrame(const uint8_t* frame, size_t length) {
  BatteryTelemetry decoded;
  if (!AntBmsDecoder::parseStatusFrame(frame, length, decoded)) {
    status_.checksumErrors += 1;
    return;
  }
  decoded.capturedAtMs = millis();
  latest_ = decoded;
  frameValidatedSinceConnect_ = true;
  status_.framesDecoded += 1;
  status_.lastFrameAtMs = decoded.capturedAtMs;
}

bool AntBmsBleClient::poll(BatteryTelemetry& telemetry) {
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

BmsBleStatus AntBmsBleClient::status() const {
  return status_;
}

}  // namespace jkbmsr