#pragma once

#include <Arduino.h>
#include <cstring>

#include "clock/SystemClock.h"

namespace jkbmsr {

// The chunked payload buffer the phone writes before `commit`.
//
// The claim token is a JWT, so no field fits one ATT write: the app sends
// offset-addressed chunks and the firmware assembles them. This is a pure,
// host-tested class because a mistake here is a half-written configuration that
// looks complete - the one outcome worse than none.
class ProvisioningBuffer {
 public:
  static constexpr size_t kCapacity = 768;

  void reset() {
    length_ = 0;
    memset(covered_, 0, sizeof covered_);
  }

  // Returns false when the chunk is empty, out of range, or overlaps a byte that
  // was already written. Overlap is refused rather than overwritten: two writers
  // disagreeing about a byte is a transport bug, and hiding it here would turn it
  // into a wrong WiFi password with no evidence.
  bool write(uint16_t offset, const uint8_t* data, size_t len) {
    if (len == 0 || data == nullptr) {
      return false;
    }
    if (static_cast<size_t>(offset) + len > kCapacity) {
      return false;
    }
    for (size_t i = 0; i < len; ++i) {
      if (isCovered(offset + i)) {
        return false;
      }
    }
    memcpy(buffer_ + offset, data, len);
    for (size_t i = 0; i < len; ++i) {
      setCovered(offset + i);
    }
    if (static_cast<size_t>(offset) + len > length_) {
      length_ = static_cast<size_t>(offset) + len;
    }
    return true;
  }

  size_t length() const { return length_; }
  const uint8_t* data() const { return buffer_; }

  // Every byte up to the highest one written is present. A gap below the top is
  // the case that would otherwise parse as valid JSON with a truncated field.
  bool complete() const {
    if (length_ == 0) {
      return false;
    }
    for (size_t i = 0; i < length_; ++i) {
      if (!isCovered(i)) {
        return false;
      }
    }
    return true;
  }

  bool isCovered(size_t index) const {
    return index < kCapacity && (covered_[index / 8] & (1u << (index % 8))) != 0;
  }

 private:
  void setCovered(size_t index) { covered_[index / 8] |= static_cast<uint8_t>(1u << (index % 8)); }

  uint8_t buffer_[kCapacity] = {};
  uint8_t covered_[kCapacity / 8] = {};
  size_t length_ = 0;
};

// The four fields the phone sends, after JSON extraction. Validation is separate
// from parsing so it can be host-tested without ArduinoJson, and so a rejected
// payload is rejected before anything is stored.
struct ProvisioningCredentials {
  String ssid;
  String password;
  String timeZone;
  String claimToken;
};

enum class CredentialError {
  none,
  ssidEmpty,
  ssidTooLong,
  passwordTooLong,
  timeZoneInvalid,
  tokenEmpty,
  tokenNotJwt,
};

// All or nothing, in the order a user would fix them: network first, then the
// zone, then the token.
inline CredentialError validateProvisioningCredentials(const ProvisioningCredentials& credentials) {
  if (credentials.ssid.length() == 0) {
    return CredentialError::ssidEmpty;
  }
  // 802.11 caps an SSID at 32 bytes; a longer one cannot be joined, so accepting
  // it would fail later where the message is worse.
  if (credentials.ssid.length() > 32) {
    return CredentialError::ssidTooLong;
  }
  // WPA2 passphrases are 8..63; 0 is an open network, which is why the range
  // starts at zero rather than at eight.
  if (credentials.password.length() > 63) {
    return CredentialError::passwordTooLong;
  }
  if (!isValidPosixTimeZone(credentials.timeZone)) {
    return CredentialError::timeZoneInvalid;
  }
  if (credentials.claimToken.length() == 0) {
    return CredentialError::tokenEmpty;
  }
  // A claim token is a signed JWT: three dot-separated, non-empty segments. This
  // is a shape check, not a signature check - the server verifies it - but it
  // turns "the app sent the wrong string" into an error at the device rather than
  // a 401 after a reboot.
  if (credentials.claimToken.length() > 512) {
    return CredentialError::tokenNotJwt;
  }
  int dots = 0;
  int segmentLength = 0;
  for (size_t i = 0; i < credentials.claimToken.length(); ++i) {
    const char c = credentials.claimToken[i];
    if (c == '.') {
      if (segmentLength == 0) {
        return CredentialError::tokenNotJwt;
      }
      ++dots;
      segmentLength = 0;
    } else {
      ++segmentLength;
    }
  }
  if (dots != 2 || segmentLength == 0) {
    return CredentialError::tokenNotJwt;
  }
  return CredentialError::none;
}

inline const char* credentialErrorName(CredentialError error) {
  switch (error) {
    case CredentialError::none:
      return "none";
    case CredentialError::ssidEmpty:
      return "ssid";
    case CredentialError::ssidTooLong:
      return "ssid";
    case CredentialError::passwordTooLong:
      return "password";
    case CredentialError::timeZoneInvalid:
      return "timezone";
    case CredentialError::tokenEmpty:
      return "token";
    case CredentialError::tokenNotJwt:
      return "token";
  }
  return "payload";
}

// Six digits, zero padded, from whatever entropy the device has. Formatted rather
// than evaluated, so the test can pin the padding - a code that prints as five
// digits is one a user cannot type.
inline String formatSetupCode(uint32_t value) {
  char out[7];
  const uint32_t sixDigits = value % 1000000u;
  snprintf(out, sizeof out, "%06lu", static_cast<unsigned long>(sixDigits));
  return String(out);
}

}  // namespace jkbmsr
