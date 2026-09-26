#include "SeplosBmsBleClient.h"

#include <NimBLEDevice.h>

#include "bms/SeplosBleDecoder.h"
#include "debug/DebugLog.h"

namespace jkbmsr {

namespace {

constexpr uint16_t kServiceUuid = 0xFF00;
constexpr uint16_t kNotifyCharacteristicUuid = 0xFF01;
constexpr uint16_t kControlCharacteristicUuid = 0xFF02;
constexpr uint8_t kFrameStart = 0x7E;

SeplosBmsBleClient* g_activeClient = nullptr;

void onNotify(NimBLERemoteCharacteristic* /*characteristic*/, uint8_t* data, size_t length,
              bool /*isNotify*/) {
  if (g_activeClient != nullptr) {
    g_activeClient->handleNotification(data, length);
  }
}

}  // namespace

void SeplosBmsBleClient::begin(const String& address) {
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
  logInfo("Seplos BMS BLE client targeting " + targetAddress_);
}

void SeplosBmsBleClient::stop() {
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

void SeplosBmsBleClient::loop() {
  if (!enabled_) {
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client != nullptr && client->isConnected()) {
    status_.connected = true;
    if (!frameValidatedSinceConnect_ && millis() - connectedAtMs_ > kFrameValidationTimeoutMs) {
      // Connected at the BLE link layer but never decoded a single valid
      // frame — JBD shares this exact service/characteristic UUID triplet,
      // so this is likely a JBD unit, not a Seplos one (see class comment).
      // Without this check the link would otherwise sit "connected" with
      // no telemetry indefinitely, since NimBLE has no reason to drop it.
      logWarn("Seplos BMS BLE connected but no valid frame after " +
              String(kFrameValidationTimeoutMs / 1000) + "s; likely wrong device, disconnecting");
      status_.lastError = "Connected but got no valid data — likely a different BLE device sharing this UUID";
      client->disconnect();
      if (configuredAddress_.length() == 0) {
        // Auto-discovered: don't just reconnect to the same wrong device —
        // exclude it and let the next scan prefer another candidate.
        excludedAddress_ = targetAddress_;
        targetAddress_ = "";
      }
      // Force an immediate retry instead of waiting out the rest of the
      // normal reconnect interval.
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

void SeplosBmsBleClient::connectIfDue() {
  if (lastConnectAttemptMs_ != 0 && millis() - lastConnectAttemptMs_ < kReconnectIntervalMs) {
    return;
  }
  lastConnectAttemptMs_ = millis();
  assemblyLength_ = 0;

  if (targetAddress_.length() == 0 && !discoverTarget()) {
    status_.state = "not_found";
    status_.lastError = "No compatible Seplos BMS advertisement found";
    logWarn("No Seplos BMS BLE advertisement found; retrying in 30s");
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client == nullptr) {
    client = NimBLEDevice::createClient();
    client->setConnectTimeout(5);
    client_ = client;
  }

  logInfo("Connecting to Seplos BMS over BLE");
  status_.state = "connecting";
  if (!client->connect(NimBLEAddress(targetAddress_.c_str(), targetAddressType_))) {
    status_.state = "connection_failed";
    status_.lastError = "BLE connection failed";
    if (configuredAddress_.length() > 0) {
      targetAddressType_ = targetAddressType_ == BLE_ADDR_PUBLIC ? BLE_ADDR_RANDOM : BLE_ADDR_PUBLIC;
      status_.addressType = targetAddressType_;
    }
    logWarn("Seplos BMS BLE connection failed; retrying in 30s");
    return;
  }

  NimBLERemoteService* service = client->getService(NimBLEUUID(kServiceUuid));
  NimBLERemoteCharacteristic* notifyChar =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kNotifyCharacteristicUuid)) : nullptr;
  NimBLERemoteCharacteristic* controlChar =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kControlCharacteristicUuid)) : nullptr;
  if (notifyChar == nullptr || controlChar == nullptr || !notifyChar->canNotify() ||
      !notifyChar->subscribe(true, onNotify)) {
    logWarn("Seplos BMS BLE service 0xFF00/0xFF01/0xFF02 unavailable; disconnecting");
    status_.state = "service_unavailable";
    status_.lastError = "FF00/FF01/FF02 service unavailable";
    client->disconnect();
    return;
  }

  logInfo("Seplos BMS BLE connected");
  status_.connected = true;
  status_.state = "connected";
  status_.lastError = "";
  status_.lastConnectedAtMs = millis();
  connectedAtMs_ = millis();
  frameValidatedSinceConnect_ = false;
  lastRequestMs_ = millis();
  sendStatusRequest();
}

bool SeplosBmsBleClient::discoverTarget() {
  // No reliable advertised-name prefix exists for Seplos (unlike JK's "JK"
  // or Daly's "DL-" prefixes) — service UUID is the only signal, and it's
  // shared with JBD's BLE profile. See the class comment in the header.
  logInfo("Scanning for Seplos BMS Bluetooth advertisements");
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
    const bool seplosService = device.haveServiceUUID() &&
                               device.isAdvertisingService(NimBLEUUID(kServiceUuid));
    if (!seplosService) {
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
    // Skip a device that just failed frame validation (see loop()), so a
    // stuck-strongest wrong device doesn't get immediately re-picked —
    // prefer the next-best candidate instead.
    if (excludedAddress_.length() > 0 && address == excludedAddress_) {
      continue;
    }
    if (device.getRSSI() > bestRssi) {
      bestRssi = device.getRSSI();
      bestAddress = address;
      bestAddressType = device.getAddress().getType();
      bestName = name;
    }
  }
  scan->clearResults();
  // Only exclude for the one discovery cycle that follows a validation
  // failure — if it's genuinely the only compatible device around, keep
  // retrying it rather than getting stuck refusing to connect to anything.
  excludedAddress_ = "";
  if (bestAddress.length() == 0) {
    return false;
  }
  targetAddress_ = bestAddress;
  targetAddressType_ = bestAddressType;
  status_.address = targetAddress_;
  status_.addressType = targetAddressType_;
  status_.advertisedName = bestName;
  status_.rssi = bestRssi;
  logInfo("Discovered Seplos BMS BLE device " + targetAddress_ + " (RSSI " + String(bestRssi) + ")");
  return true;
}

bool SeplosBmsBleClient::sendStatusRequest() {
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
  uint8_t frame[SeplosBleDecoder::kRequestFrameSize];
  SeplosBleDecoder::buildSingleMachineDataRequest(frame);
  return controlChar->writeValue(frame, sizeof(frame), false);
}

void SeplosBmsBleClient::handleNotification(const uint8_t* data, size_t length) {
  if (data == nullptr || length == 0) {
    return;
  }
  if (assemblyLength_ + length > kAssemblyBufferSize) {
    assemblyLength_ = 0;
  }
  // A new frame preamble restarts assembly.
  if (length >= 1 && data[0] == kFrameStart) {
    assemblyLength_ = 0;
  }
  if (assemblyLength_ + length > kAssemblyBufferSize) {
    // A single notification chunk larger than the buffer; nothing to do.
    return;
  }
  memcpy(assemblyBuffer_ + assemblyLength_, data, length);
  assemblyLength_ += length;

  // Seplos frames are variable-length: the payload length field (bytes 5-6,
  // big-endian) determines the full frame size, unlike Daly's fixed-size
  // status response.
  if (assemblyLength_ >= 7) {
    const uint16_t declaredPayloadLen =
        static_cast<uint16_t>((static_cast<uint16_t>(assemblyBuffer_[5]) << 8) | assemblyBuffer_[6]);
    const size_t frameLen = 7 + static_cast<size_t>(declaredPayloadLen) + 2 + 1;
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

void SeplosBmsBleClient::processFrame(const uint8_t* frame, size_t length) {
  BatteryTelemetry decoded;
  if (!SeplosBleDecoder::parseSingleMachineDataFrame(frame, length, decoded)) {
    status_.checksumErrors += 1;
    return;
  }
  decoded.capturedAtMs = millis();
  latest_ = decoded;
  frameValidatedSinceConnect_ = true;
  status_.framesDecoded += 1;
  status_.lastFrameAtMs = decoded.capturedAtMs;
}

bool SeplosBmsBleClient::poll(BatteryTelemetry& telemetry) {
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

BmsBleStatus SeplosBmsBleClient::status() const {
  return status_;
}

}  // namespace jkbmsr
