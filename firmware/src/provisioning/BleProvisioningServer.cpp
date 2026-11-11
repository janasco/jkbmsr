#include "cloud/BleProvisioningServer.h"

#include <ArduinoJson.h>
#include <Preferences.h>

#include "cloud/ProvisioningPayload.h"
#include "cloud/ProvisioningSession.h"

namespace jkbmsr {

namespace {

// Must match firmware/docs/ble-provisioning.md and the app's
// provisioning_protocol.dart. A changed UUID on one side is a scan that finds
// nothing, which is the least diagnosable failure in the whole flow.
constexpr const char* kServiceUuid = "9a1f0000-7c3b-4d2e-9f10-6b5a8e2c4d70";
constexpr const char* kStatusUuid = "9a1f0001-7c3b-4d2e-9f10-6b5a8e2c4d70";
constexpr const char* kSetupUuid = "9a1f0002-7c3b-4d2e-9f10-6b5a8e2c4d70";
constexpr const char* kPayloadUuid = "9a1f0003-7c3b-4d2e-9f10-6b5a8e2c4d70";
constexpr const char* kCommandUuid = "9a1f0004-7c3b-4d2e-9f10-6b5a8e2c4d70";

constexpr const char* kSetupNamespace = "jkbmsr-setup";
constexpr const char* kSetupCodeKey = "code";

constexpr size_t kSetupCodeLength = 6;

}  // namespace

String BleProvisioningServer::advertisedName(const String& deviceId) {
  String suffix = deviceId;
  const int dash = suffix.lastIndexOf('-');
  if (dash >= 0 && dash + 1 < static_cast<int>(suffix.length())) {
    suffix = suffix.substring(dash + 1);
  }
  suffix.toUpperCase();
  if (suffix.length() > 4) {
    suffix = suffix.substring(suffix.length() - 4);
  }
  return String("JKBMSR-Setup-") + suffix;
}

bool BleProvisioningServer::begin(const String& setupCode, const String& name) {
  if (active_) {
    return true;
  }

  // Idempotent in NimBLE 2.x, so the pack link's client can initialise later
  // without resetting the host under this service.
  NimBLEDevice::init("jkbmsr-gateway");

  server_ = NimBLEDevice::createServer();
  if (server_ == nullptr) {
    return false;
  }
  server_->setCallbacks(this);

  service_ = server_->createService(kServiceUuid);
  if (service_ == nullptr) {
    return false;
  }

  statusChar_ = service_->createCharacteristic(
      kStatusUuid, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  setupChar_ = service_->createCharacteristic(kSetupUuid, NIMBLE_PROPERTY::WRITE);
  payloadChar_ = service_->createCharacteristic(kPayloadUuid, NIMBLE_PROPERTY::WRITE);
  commandChar_ = service_->createCharacteristic(kCommandUuid, NIMBLE_PROPERTY::WRITE);

  if (statusChar_ == nullptr || setupChar_ == nullptr || payloadChar_ == nullptr ||
      commandChar_ == nullptr) {
    return false;
  }

  for (NimBLECharacteristic* characteristic :
       {statusChar_, setupChar_, payloadChar_, commandChar_}) {
    characteristic->setCallbacks(this);
  }

  service_->start();
  session_ = ProvisioningSession(setupCode);
  buffer_.reset();
  outcomeReady_ = false;
  publishStatus("advertising");

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->reset();
  advertising->addServiceUUID(kServiceUuid);
  advertising->setName(name.c_str());
  advertising->start();

  active_ = true;
  return true;
}

void BleProvisioningServer::end() {
  if (!active_) {
    return;
  }
  active_ = false;
  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  if (advertising != nullptr) {
    advertising->stop();
  }
  // The GATT service is left allocated rather than torn down: the radio host
  // stays up for the pack link, and re-creating a service with the same UUID
  // after removing it is the kind of teardown that works on the bench and fails
  // on the second attempt. A gateway that finishes setup restarts anyway.
  publishStatus("running");
}

void BleProvisioningServer::tick(uint32_t nowMs) {
  if (!active_) {
    return;
  }
  if (session_.tick(nowMs)) {
    // The window closed. Clear the buffer so a later attempt cannot commit a
    // half-written payload from this one.
    buffer_.reset();
    publishStatus("advertising");
  }
}

ProvisioningOutcome BleProvisioningServer::takeOutcome() {
  ProvisioningOutcome outcome = outcome_;
  outcomeReady_ = false;
  outcome_ = ProvisioningOutcome();
  return outcome;
}

#if defined(NIMBLE_CPP_VERSION_MAJOR) && NIMBLE_CPP_VERSION_MAJOR >= 2
void BleProvisioningServer::onConnect(NimBLEServer* server, NimBLEConnInfo& connInfo) {
  (void)server;
  (void)connInfo;
#else
void BleProvisioningServer::onConnect(NimBLEServer* server) {
  (void)server;
#endif
  if (!active_) {
    return;
  }
  if (!session_.onConnected(millis())) {
    // One phone at a time: the radio is shared with the pack link, and a second
    // connection is paid for by telemetry.
    publishStatus("failed:busy");
    return;
  }
  publishStatus("connected");
}

#if defined(NIMBLE_CPP_VERSION_MAJOR) && NIMBLE_CPP_VERSION_MAJOR >= 2
void BleProvisioningServer::onDisconnect(NimBLEServer* server, NimBLEConnInfo& connInfo,
                                         int reason) {
  (void)server;
  (void)connInfo;
  (void)reason;
#else
void BleProvisioningServer::onDisconnect(NimBLEServer* server) {
  (void)server;
#endif
  session_.onDisconnected();
  buffer_.reset();
  if (active_) {
    publishStatus("advertising");
  }
}

#if defined(NIMBLE_CPP_VERSION_MAJOR) && NIMBLE_CPP_VERSION_MAJOR >= 2
void BleProvisioningServer::onWrite(NimBLECharacteristic* characteristic,
                                    NimBLEConnInfo& connInfo) {
  (void)connInfo;
#else
void BleProvisioningServer::onWrite(NimBLECharacteristic* characteristic) {
#endif
  if (!active_) {
    return;
  }
  const NimBLEAttValue& value = characteristic->getValue();
  const uint32_t nowMs = millis();

  if (characteristic == setupChar_) {
    handleSetupCode(value.data(), value.size(), nowMs);
    return;
  }
  if (characteristic == payloadChar_) {
    handlePayload(value.data(), value.size());
    return;
  }
  if (characteristic == commandChar_) {
    handleCommit(nowMs);
  }
}

void BleProvisioningServer::handleSetupCode(const uint8_t* data, size_t length,
                                            uint32_t nowMs) {
  if (length != kSetupCodeLength) {
    publishStatus("failed:code");
    return;
  }
  String code;
  code.reserve(length);
  for (size_t i = 0; i < length; ++i) {
    code += static_cast<char>(data[i]);
  }

  switch (session_.submitSetupCode(code, nowMs)) {
    case SetupCodeResult::accepted:
      publishStatus("authenticated");
      break;
    case SetupCodeResult::rejected:
      publishStatus("failed:code");
      break;
    case SetupCodeResult::lockedOut:
      // Three strikes: the session is back to advertising and no write will be
      // accepted until a new connection.
      publishStatus("failed:code");
      break;
    case SetupCodeResult::notConnected:
      publishStatus("failed:payload");
      break;
  }
}

void BleProvisioningServer::handlePayload(const uint8_t* data, size_t length) {
  if (!session_.credentialsWritable()) {
    // The whole point of the code: a phone that connected by accident cannot
    // change this gateway's network.
    publishStatus("failed:code");
    return;
  }
  if (length < 3) {
    publishStatus("failed:payload");
    return;
  }
  const uint16_t offset = static_cast<uint16_t>(data[0]) |
                          static_cast<uint16_t>(data[1] << 8);
  if (!buffer_.write(offset, data + 2, length - 2)) {
    publishStatus("failed:payload");
  }
}

void BleProvisioningServer::handleCommit(uint32_t nowMs) {
  if (!session_.credentialsWritable()) {
    publishStatus("failed:code");
    return;
  }
  if (!buffer_.complete()) {
    publishStatus("failed:payload");
    return;
  }

  JsonDocument document;
  if (deserializeJson(document, buffer_.data(), buffer_.length()) !=
      DeserializationError::Ok) {
    publishStatus("failed:json");
    return;
  }

  ProvisioningCredentials credentials;
  credentials.ssid = document["ssid"].as<String>();
  credentials.password = document["password"].as<String>();
  credentials.timeZone = document["timeZone"].as<String>();
  credentials.claimToken = document["claimToken"].as<String>();

  const CredentialError error = validateProvisioningCredentials(credentials);
  if (error != CredentialError::none) {
    // All or nothing: a rejected field must not leave a half-written config.
    buffer_.reset();
    publishStatus(String("failed:") + credentialErrorName(error));
    return;
  }

  if (!session_.commit(nowMs)) {
    publishStatus("failed:payload");
    return;
  }

  outcome_.applied = true;
  outcome_.ssid = credentials.ssid;
  outcome_.password = credentials.password;
  outcome_.timeZone = credentials.timeZone;
  outcome_.claimToken = credentials.claimToken;
  outcomeReady_ = true;
  publishStatus("applying");
}

void BleProvisioningServer::publishStatus(const String& text) {
  if (statusChar_ == nullptr) {
    return;
  }
  statusChar_->setValue(text.c_str());
  if (server_ != nullptr) {
    statusChar_->notify();
  }
}

String loadOrCreateSetupCode() {
  Preferences prefs;
  String code;
  if (prefs.begin(kSetupNamespace, false)) {
    code = prefs.getString(kSetupCodeKey, "");
    if (code.length() != kSetupCodeLength) {
      code = formatSetupCode(esp_random());
      prefs.putString(kSetupCodeKey, code);
    }
    prefs.end();
  }
  if (code.length() != kSetupCodeLength) {
    // NVS unavailable: a per-boot code still protects this session, it just
    // does not survive the move from USB power to the pack.
    code = formatSetupCode(esp_random());
  }
  return code;
}

void resetSetupCode() {
  Preferences prefs;
  if (prefs.begin(kSetupNamespace, false)) {
    prefs.remove(kSetupCodeKey);
    prefs.end();
  }
}

}  // namespace jkbmsr
