#include "JkBmsBleClient.h"

#include <NimBLEDevice.h>

#include "debug/DebugLog.h"

namespace jkbmsr {

namespace {

constexpr uint16_t kServiceUuid = 0xFFE0;
constexpr uint16_t kCharacteristicUuid = 0xFFE1;

JkBmsBleClient* g_activeClient = nullptr;

void onNotify(NimBLERemoteCharacteristic* /*characteristic*/, uint8_t* data, size_t length,
              bool /*isNotify*/) {
  if (g_activeClient != nullptr) {
    g_activeClient->handleNotification(data, length);
  }
}

// 20-byte command frame: 0xAA 0x55 0x90 0xEB header, register, length, value,
// additive 8-bit checksum in the last byte.
void buildCommand(JkBmsReadOnlyCommand command, uint8_t frame[20]) {
  memset(frame, 0, 20);
  frame[0] = 0xAA;
  frame[1] = 0x55;
  frame[2] = 0x90;
  frame[3] = 0xEB;
  frame[4] = static_cast<uint8_t>(command);
  frame[19] = jk02Checksum(frame, 19);
}

}  // namespace

void JkBmsBleClient::begin(const String& address) {
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
  if (!enabled_) {
    return;
  }
  if (!stackInitialized_) {
    NimBLEDevice::init("");
    stackInitialized_ = true;
  }
  g_activeClient = this;
  logInfo("JK-BMS BLE client targeting " + targetAddress_);
}

void JkBmsBleClient::stop() {
  enabled_ = false;
  status_.enabled = false;
  status_.connected = false;
  status_.state = "disabled";
  deviceInfoReceived_ = false;
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

void JkBmsBleClient::loop() {
  if (!enabled_) {
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client != nullptr && client->isConnected()) {
    status_.connected = true;
    // The layout depends on device info; keep asking until it arrives.
    if (!deviceInfoReceived_ && millis() - lastCommandMs_ >= 5000) {
      lastCommandMs_ = millis();
      sendReadOnlyCommand(JkBmsReadOnlyCommand::kDeviceInfo);
    }
    return;
  }

  status_.connected = false;
  if (status_.state == "connected") {
    status_.state = "disconnected";
  }
  connectIfDue();
}

void JkBmsBleClient::connectIfDue() {
  if (lastConnectAttemptMs_ != 0 && millis() - lastConnectAttemptMs_ < kReconnectIntervalMs) {
    return;
  }
  lastConnectAttemptMs_ = millis();
  deviceInfoReceived_ = false;
  assemblyLength_ = 0;

  if (targetAddress_.length() == 0 && !discoverTarget()) {
    status_.state = "not_found";
    status_.lastError = "No compatible JK-BMS advertisement found";
    logWarn("No JK-BMS BLE advertisement found; retrying in 30s");
    return;
  }

  auto* client = static_cast<NimBLEClient*>(client_);
  if (client == nullptr) {
    client = NimBLEDevice::createClient();
    client->setConnectTimeout(5);
    client_ = client;
  }

  logInfo("Connecting to JK-BMS over BLE");
  status_.state = "connecting";
  if (!client->connect(NimBLEAddress(targetAddress_.c_str(), targetAddressType_))) {
    status_.state = "connection_failed";
    status_.lastError = "BLE connection failed";
    // A manually entered MAC does not carry BLE's public/random address type.
    // Alternate on retries; auto-discovery preserves the advertised type.
    if (configuredAddress_.length() > 0) {
      targetAddressType_ = targetAddressType_ == BLE_ADDR_PUBLIC ? BLE_ADDR_RANDOM : BLE_ADDR_PUBLIC;
      status_.addressType = targetAddressType_;
    }
    logWarn("JK-BMS BLE connection failed; retrying in 30s");
    return;
  }

  NimBLERemoteService* service = client->getService(NimBLEUUID(kServiceUuid));
  NimBLERemoteCharacteristic* characteristic =
      service != nullptr ? service->getCharacteristic(NimBLEUUID(kCharacteristicUuid)) : nullptr;
  if (characteristic == nullptr || !characteristic->canNotify() ||
      !characteristic->subscribe(true, onNotify)) {
    logWarn("JK-BMS BLE service 0xFFE0/0xFFE1 unavailable; disconnecting");
    status_.state = "service_unavailable";
    status_.lastError = "FFE0/FFE1 service unavailable";
    client->disconnect();
    return;
  }

  logInfo("JK-BMS BLE connected");
  status_.connected = true;
  status_.state = "connected";
  status_.lastError = "";
  status_.lastConnectedAtMs = millis();
  lastCommandMs_ = millis();
  sendReadOnlyCommand(JkBmsReadOnlyCommand::kDeviceInfo);
}

bool JkBmsBleClient::discoverTarget() {
  logInfo("Scanning for JK-BMS Bluetooth advertisements");
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
    const bool jkService = device.haveServiceUUID() &&
                           device.isAdvertisingService(NimBLEUUID(kServiceUuid));
    const String name = device.haveName() ? String(device.getName().c_str()) : String();
    const bool jkName = name.startsWith("JK") || name.startsWith("jk");
    if (!(jkService || jkName)) {
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
  logInfo("Discovered JK-BMS BLE device " + targetAddress_ + " (RSSI " + String(bestRssi) + ")");
  return true;
}

bool JkBmsBleClient::sendReadOnlyCommand(JkBmsReadOnlyCommand command) {
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
  uint8_t frame[20];
  buildCommand(command, frame);
  return characteristic->writeValue(frame, sizeof(frame), false);
}

void JkBmsBleClient::handleNotification(const uint8_t* data, size_t length) {
  if (data == nullptr || length == 0) {
    return;
  }
  if (assemblyLength_ + length > kAssemblyBufferSize) {
    assemblyLength_ = 0;
  }
  // A new frame preamble restarts assembly.
  if (length >= 4 && data[0] == 0x55 && data[1] == 0xAA && data[2] == 0xEB && data[3] == 0x90) {
    assemblyLength_ = 0;
  }
  memcpy(assemblyBuffer_ + assemblyLength_, data, length);
  assemblyLength_ += length;

  if (assemblyLength_ >= kJk02FrameSize) {
    processFrame(assemblyBuffer_, kJk02FrameSize);
    assemblyLength_ = 0;
  }
}

void JkBmsBleClient::processFrame(const uint8_t* frame, size_t length) {
  if (!jk02FrameValid(frame, length)) {
    status_.checksumErrors += 1;
    return;
  }

  switch (jk02FrameTypeOf(frame, length)) {
    case Jk02FrameType::kDeviceInfo: {
      if (decodeJk02DeviceInfo(frame, length, deviceInfo_)) {
        const bool firstDeviceInfo = !deviceInfoReceived_;
        const bool identityChanged = status_.hardwareVersion != deviceInfo_.hardwareVersion;
        deviceInfoReceived_ = true;
        status_.hardwareVersion = deviceInfo_.hardwareVersion;
        status_.softwareVersion = deviceInfo_.softwareVersion;
        status_.is32s = deviceInfo_.is32s;
        if (firstDeviceInfo || identityChanged) {
          logInfo("JK-BMS identified: hw " + deviceInfo_.hardwareVersion + " sw " +
                  deviceInfo_.softwareVersion + (deviceInfo_.is32s ? " (32S layout)" : " (24S layout)"));
        }
        if (firstDeviceInfo) {
          sendReadOnlyCommand(JkBmsReadOnlyCommand::kSettingsAndTelemetryStream);
        }
      }
      break;
    }
    case Jk02FrameType::kCellInfo: {
      if (!deviceInfoReceived_) {
        // Layout unknown until the hardware version arrives.
        return;
      }
      BatteryTelemetry decoded;
      if (decodeJk02CellInfo(frame, length, deviceInfo_.is32s, decoded)) {
        decoded.capturedAtMs = millis();
        decoded.bmsSoftwareVersion = deviceInfo_.softwareVersion;
        latest_ = decoded;
        status_.framesDecoded += 1;
        status_.lastFrameAtMs = decoded.capturedAtMs;
      }
      break;
    }
    default:
      break;
  }
}

bool JkBmsBleClient::poll(BatteryTelemetry& telemetry) {
  if (!enabled_) {
    return false;
  }
  // The BMS auto-streams cell-info frames continuously once the one-time 0x96
  // request from processFrame() starts the stream, so no per-poll request is
  // needed (every 0x96 the hardware accepts is an audible beep). Only
  // re-request when the stream stalls; non-auto-streaming units fall back to
  // a fresh request on each poll and keep the old cadence.
  if (deviceInfoReceived_ && (!latest_.valid || millis() - latest_.capturedAtMs > kStreamStaleMs)) {
    sendReadOnlyCommand(JkBmsReadOnlyCommand::kSettingsAndTelemetryStream);
  }
  if (!latest_.valid || millis() - latest_.capturedAtMs > kSampleFreshMs) {
    return false;
  }
  telemetry = latest_;
  return true;
}

BmsBleStatus JkBmsBleClient::status() const {
  return status_;
}

}  // namespace jkbmsr
