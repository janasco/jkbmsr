#include "ImprovProtocol.h"

namespace jkbmsr {
namespace improv {

namespace {

uint8_t checksum(const uint8_t* bytes, size_t count) {
  uint32_t sum = 0;
  for (size_t i = 0; i < count; ++i) {
    sum += bytes[i];
  }
  return static_cast<uint8_t>(sum & 0xFF);
}

}  // namespace

void Parser::reset() {
  phase_ = Phase::Header;
  headerMatched_ = 0;
  length_ = 0;
  dataRead_ = 0;
}

bool Parser::feed(uint8_t byte) {
  switch (phase_) {
    case Phase::Header:
      if (byte == kHeader[headerMatched_]) {
        buf_[headerMatched_] = byte;
        headerMatched_++;
        if (headerMatched_ == sizeof(kHeader)) {
          phase_ = Phase::Version;
        }
      } else {
        // Restart header matching; a stray byte may itself be the header start.
        headerMatched_ = (byte == kHeader[0]) ? 1 : 0;
        if (headerMatched_ == 1) {
          buf_[0] = byte;
        }
      }
      return false;

    case Phase::Version:
      if (byte != kVersion) {
        reset();
        return false;
      }
      buf_[6] = byte;
      phase_ = Phase::Type;
      return false;

    case Phase::Type:
      buf_[7] = byte;
      type_ = static_cast<PacketType>(byte);
      phase_ = Phase::Length;
      return false;

    case Phase::Length:
      if (byte > kMaxData) {
        reset();
        return false;
      }
      buf_[8] = byte;
      length_ = byte;
      dataRead_ = 0;
      phase_ = (length_ == 0) ? Phase::Checksum : Phase::Data;
      return false;

    case Phase::Data:
      buf_[kDataOffset + dataRead_] = byte;
      dataRead_++;
      if (dataRead_ == length_) {
        phase_ = Phase::Checksum;
      }
      return false;

    case Phase::Checksum: {
      const uint8_t expected = checksum(buf_, kDataOffset + length_);
      const bool valid = (expected == byte);
      // Ready for the next packet regardless; the decoded fields remain
      // readable until the next feed() overwrites them.
      phase_ = Phase::Header;
      headerMatched_ = 0;
      return valid;
    }
  }
  return false;
}

size_t buildPacket(PacketType type, const uint8_t* data, uint8_t len, uint8_t* out) {
  if (len > kMaxData) {
    return 0;
  }
  size_t pos = 0;
  for (size_t i = 0; i < sizeof(kHeader); ++i) {
    out[pos++] = kHeader[i];
  }
  out[pos++] = kVersion;
  out[pos++] = static_cast<uint8_t>(type);
  out[pos++] = len;
  for (uint8_t i = 0; i < len; ++i) {
    out[pos++] = data[i];
  }
  out[pos] = checksum(out, pos);
  pos++;
  return pos;
}

uint8_t encodeRpcResult(Command command, const String* strings, size_t count, uint8_t* dataOut) {
  // Reserve dataOut[0]=command, dataOut[1]=payload length, payload follows.
  size_t payload = 0;
  for (size_t i = 0; i < count; ++i) {
    const size_t stringLen = strings[i].length();
    // +1 for the per-string length prefix. Bound to the packet data budget.
    if (stringLen > 255 || (2 + payload + 1 + stringLen) > kMaxData) {
      return 0;
    }
    dataOut[2 + payload] = static_cast<uint8_t>(stringLen);
    payload++;
    memcpy(&dataOut[2 + payload], strings[i].c_str(), stringLen);
    payload += stringLen;
  }
  dataOut[0] = static_cast<uint8_t>(command);
  dataOut[1] = static_cast<uint8_t>(payload);
  return static_cast<uint8_t>(2 + payload);
}

bool parseWifiSettings(const uint8_t* cmdData, uint8_t cmdLen, String& ssid, String& password) {
  if (cmdLen < 1) {
    return false;
  }
  const uint8_t ssidLen = cmdData[0];
  if (1 + ssidLen + 1 > cmdLen) {
    return false;
  }
  const uint8_t passLen = cmdData[1 + ssidLen];
  if (1 + ssidLen + 1 + passLen > cmdLen) {
    return false;
  }

  ssid = "";
  ssid.reserve(ssidLen);
  for (uint8_t i = 0; i < ssidLen; ++i) {
    ssid += static_cast<char>(cmdData[1 + i]);
  }

  password = "";
  password.reserve(passLen);
  const uint8_t passStart = 1 + ssidLen + 1;
  for (uint8_t i = 0; i < passLen; ++i) {
    password += static_cast<char>(cmdData[passStart + i]);
  }
  return ssidLen > 0;
}

}  // namespace improv
}  // namespace jkbmsr
