#pragma once

#include <Arduino.h>

// Minimal, dependency-free implementation of the Improv Wi-Fi *Serial*
// protocol (https://www.improv-wifi.com/serial/). The browser flasher
// (ESP Web Tools) speaks this over the same USB/Web-Serial connection it just
// flashed on, so a device with no Wi-Fi credentials can be provisioned without
// a serial monitor or an app. Implemented in-tree to match the codebase's
// minimal-dependency style and to keep the framing logic unit-testable over a
// fake Stream (no WiFi.h dependency lives here).

namespace jkbmsr {
namespace improv {

constexpr uint8_t kHeader[6] = {'I', 'M', 'P', 'R', 'O', 'V'};
constexpr uint8_t kVersion = 1;

// Largest data field we build or accept. The onboarding URL and device-info
// strings are the biggest payloads and stay well under this.
constexpr uint8_t kMaxData = 240;

enum class PacketType : uint8_t {
  CurrentState = 0x01,
  ErrorState = 0x02,
  RpcCommand = 0x03,
  RpcResult = 0x04,
};

enum class State : uint8_t {
  Ready = 0x02,
  Provisioning = 0x03,
  Provisioned = 0x04,
};

enum class Error : uint8_t {
  None = 0x00,
  InvalidRpcPacket = 0x01,
  UnknownRpcCommand = 0x02,
  UnableToConnect = 0x03,
  Unknown = 0xFF,
};

enum class Command : uint8_t {
  WifiSettings = 0x01,
  RequestState = 0x02,
  RequestDeviceInfo = 0x03,
  RequestScan = 0x04,
  // Custom command, deliberately outside the Improv spec's 0x01–0x05 range:
  // the browser flasher hands the gateway an account-bound claim token over the
  // same serial session, which the gateway persists and presents on first
  // registration. Unknown to stock Improv clients, which simply won't send it.
  SetClaimToken = 0x20,
};

// Incremental byte parser. Feed one received byte at a time; feed() returns
// true exactly once, when a complete checksum-valid packet has been assembled.
// The decoded packet is then readable via type()/data()/length() until the
// next feed() call.
class Parser {
 public:
  bool feed(uint8_t byte);
  PacketType type() const { return type_; }
  const uint8_t* data() const { return &buf_[kDataOffset]; }
  uint8_t length() const { return length_; }
  void reset();

 private:
  static constexpr size_t kDataOffset = 9;  // header(6)+version(1)+type(1)+length(1)
  enum class Phase { Header, Version, Type, Length, Data, Checksum };

  Phase phase_ = Phase::Header;
  uint8_t buf_[kDataOffset + kMaxData + 1] = {};
  uint8_t headerMatched_ = 0;
  uint8_t length_ = 0;
  uint8_t dataRead_ = 0;
  PacketType type_ = PacketType::CurrentState;
};

// Serialize a full packet into `out` (must be at least 9 + len + 1 bytes) and
// return the number of bytes written. `len` must be <= kMaxData.
size_t buildPacket(PacketType type, const uint8_t* data, uint8_t len, uint8_t* out);

// Build the data field of an RPC result: [command][payloadLen][ strings... ]
// where each string is length-prefixed. Returns the data-field length, or 0 if
// the encoded payload would exceed kMaxData. `count` may be 0 (empty result,
// used to terminate a scan with no networks).
uint8_t encodeRpcResult(Command command, const String* strings, size_t count, uint8_t* dataOut);

// Parse a WIFI_SETTINGS command payload ([ssidLen][ssid][passLen][pass]).
// Returns false if the buffer is malformed.
bool parseWifiSettings(const uint8_t* cmdData, uint8_t cmdLen, String& ssid, String& password);

// Parse a SET_CLAIM_TOKEN command payload ([tokenLen][token]). Returns false if
// the buffer is malformed or the token is empty.
bool parseClaimToken(const uint8_t* cmdData, uint8_t cmdLen, String& token);

}  // namespace improv
}  // namespace jkbmsr
