#include "ProvisioningManager.h"

#include "FirmwareVersion.h"

namespace jkbmsr {

using improv::Command;
using improv::Error;
using improv::PacketType;
using improv::State;

String buildOnboardUrl(const String& deviceId, const String& claimCode) {
  // deviceId (jkbmsr-<hex>) and claimCode (base32, unambiguous alphabet) are
  // already URL-safe, so no percent-encoding is required.
  return "https://web.jkbmsr.com/onboard?device=" + deviceId + "&code=" + claimCode;
}

void ProvisioningManager::begin(
    Stream& io,
    const String& deviceId,
    const String& claimCode,
    bool announceReady,
    bool claimReady) {
  io_ = &io;
  deviceId_ = deviceId;
  claimCode_ = claimCode;
  parser_.reset();
  state_ = State::Ready;
  announced_ = !announceReady;
  claimReady_ = claimReady;
}

bool ProvisioningManager::poll(
    const ConnectFn& tryConnect,
    String& outSsid,
    String& outPassword,
    const ScanFn& scanNetworks) {
  if (io_ == nullptr) {
    return false;
  }

  // Announce readiness once so a freshly-attached browser detects Improv even
  // if it never sends an explicit "request state".
  if (!announced_) {
    sendCurrentState(state_);
    announced_ = true;
  }

  while (io_->available() > 0) {
    const int raw = io_->read();
    if (raw < 0) {
      break;
    }
    if (!parser_.feed(static_cast<uint8_t>(raw))) {
      continue;
    }
    if (parser_.type() != PacketType::RpcCommand) {
      continue;  // We only act on host commands.
    }

    const uint8_t* data = parser_.data();
    const uint8_t length = parser_.length();
    if (length < 2) {
      sendError(Error::InvalidRpcPacket);
      continue;
    }
    const Command command = static_cast<Command>(data[0]);
    const uint8_t cmdLen = data[1];
    if (static_cast<size_t>(2) + cmdLen > length) {
      sendError(Error::InvalidRpcPacket);
      continue;
    }
    const uint8_t* cmdData = data + 2;

    switch (command) {
      case Command::RequestState:
        sendCurrentState(state_);
        break;
      case Command::RequestDeviceInfo:
        sendDeviceInfo();
        break;
      case Command::RequestScan:
        sendWifiNetworks(scanNetworks);
        break;
      case Command::WifiSettings: {
        bool done = false;
        handleWifiSettings(cmdData, cmdLen, tryConnect, outSsid, outPassword, done);
        if (done) {
          return true;
        }
        break;
      }
      default:
        sendError(Error::UnknownRpcCommand);
        break;
    }
  }
  return false;
}

void ProvisioningManager::sendWifiNetworks(const ScanFn& scanNetworks) {
  constexpr size_t kMaxNetworks = 20;
  Network networks[kMaxNetworks];
  const size_t count = scanNetworks ? scanNetworks(networks, kMaxNetworks) : 0;

  // Improv sends each network separately to stay within the one-byte packet
  // length budget. The three fields are SSID, RSSI, and whether credentials
  // are required. An empty result terminates the list.
  for (size_t index = 0; index < count && index < kMaxNetworks; ++index) {
    if (networks[index].ssid.length() == 0) continue;
    const String fields[] = {
        networks[index].ssid,
        String(networks[index].rssi),
        networks[index].secure ? "YES" : "NO",
    };
    sendRpcResult(Command::RequestScan, fields, 3);
  }
  sendRpcResult(Command::RequestScan, nullptr, 0);
}

void ProvisioningManager::handleWifiSettings(const uint8_t* cmdData, uint8_t cmdLen,
                                             const ConnectFn& tryConnect, String& outSsid,
                                             String& outPassword, bool& done) {
  String ssid;
  String password;
  if (!improv::parseWifiSettings(cmdData, cmdLen, ssid, password)) {
    sendError(Error::InvalidRpcPacket);
    return;
  }

  state_ = State::Provisioning;
  sendCurrentState(state_);

  if (tryConnect && tryConnect(ssid, password)) {
    state_ = State::Provisioned;
    sendCurrentState(state_);
    const String url = buildOnboardUrl(deviceId_, claimCode_);
    sendRpcResult(Command::WifiSettings, &url, 1);
    outSsid = ssid;
    outPassword = password;
    done = true;
    return;
  }

  // Connection failed: report the error and return to Ready so the browser can
  // prompt for corrected credentials.
  sendError(Error::UnableToConnect);
  state_ = State::Ready;
  sendCurrentState(state_);
}

void ProvisioningManager::sendCurrentState(State state) {
  const uint8_t payload = static_cast<uint8_t>(state);
  uint8_t packet[improv::kMaxData + 16];
  const size_t written = improv::buildPacket(PacketType::CurrentState, &payload, 1, packet);
  io_->write(packet, written);
}

void ProvisioningManager::sendError(Error error) {
  const uint8_t payload = static_cast<uint8_t>(error);
  uint8_t packet[improv::kMaxData + 16];
  const size_t written = improv::buildPacket(PacketType::ErrorState, &payload, 1, packet);
  io_->write(packet, written);
}

void ProvisioningManager::sendRpcResult(Command command, const String* strings, size_t count) {
  uint8_t data[improv::kMaxData];
  const uint8_t dataLen = improv::encodeRpcResult(command, strings, count, data);
  if (dataLen == 0 && count != 0) {
    return;  // Payload overflowed; drop rather than emit a malformed packet.
  }
  uint8_t packet[improv::kMaxData + 16];
  const size_t written = improv::buildPacket(PacketType::RpcResult, data, dataLen, packet);
  io_->write(packet, written);
}

void ProvisioningManager::sendDeviceInfo() {
  const String onboardUrl = buildOnboardUrl(deviceId_, claimCode_);
  const String strings[] = {
      String("JKBMSR"),               // firmware name
      String(kFirmwareVersion),        // firmware version
#if defined(ARDUINO_ARCH_ESP8266)
      String("ESP8266"),               // chip family
#else
      String("ESP32"),                 // chip family
#endif
      deviceId_,                       // device name
      onboardUrl,                      // physical-possession claim handoff
      claimReady_ ? "claim-ready" : "wifi-required",
  };
  sendRpcResult(Command::RequestDeviceInfo, strings, 6);
}

}  // namespace jkbmsr
