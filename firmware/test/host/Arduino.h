#pragma once
// Minimal Arduino host shim — NOT a PlatformIO/Arduino replacement.
//
// Purpose: the pure-decode unit suites (test/test_*/) only need a handful of
// Arduino surface types. Until now CI ran
//   pio test -e dev --without-uploading --without-testing
// where --without-testing skips *execution*, so every "[PASSED]" line was a
// compile result and the run summary read "0 test cases: 0 succeeded". No
// firmware test had ever actually run. scripts/run-host-tests.sh compiles the
// same suites natively with -fsanitize=address,undefined so decoder bugs
// surface without hardware and without the ESP toolchain.
//
// This is a test scaffold only. It must never be on the include path for a
// real firmware build.

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

// Arduino preprocessor constants used by protocol code.
#define DEC 10
#define HEX 16

// PROGMEM/F() only exist to move string literals into flash on AVR. On a host
// the literal is already in .rodata, so F() is the identity. CaptivePortal's
// HTML page is one big pile of F() literals.
#define F(str) (str)
#define PROGMEM

using byte = uint8_t;

inline unsigned long millis() { return 0; }
inline unsigned long micros() { return 0; }
inline void delay(unsigned long) {}
inline void delayMicroseconds(unsigned int) {}
inline void yield() {}

// GPIO surface used by the provisioning/reset sources. Reads return "not
// pressed" so a host run never has to model a BOOT button.
#define LOW 0
#define HIGH 1
#define INPUT 0
#define OUTPUT 1
#define INPUT_PULLUP 2
inline void pinMode(uint8_t, uint8_t) {}
inline void digitalWrite(uint8_t, uint8_t) {}
inline int digitalRead(uint8_t) { return HIGH; }

namespace host_detail {

// Arduino's String(unsigned char, int base) formats uppercase, no prefix,
// zero-padded only by the caller's request. Shared by the base and
// non-base numeric constructors below.
inline std::string encodeUnsigned(unsigned long value, int base) {
  if (base < 2 || base > 36) base = DEC;
  std::string digits;
  do {
    const unsigned digit = value % static_cast<unsigned>(base);
    digits.push_back(static_cast<char>(digit < 10 ? '0' + digit : 'A' + digit - 10));
    value /= static_cast<unsigned>(base);
  } while (value != 0);
  std::reverse(digits.begin(), digits.end());
  return digits;
}

}  // namespace host_detail

class String : public std::string {
 public:
  String() = default;
  String(const char* s) : std::string(s ? s : "") {}
  String(const std::string& s) : std::string(s) {}
  String(char c) : std::string(1, c) {}
  String(unsigned char c) : std::string(1, static_cast<char>(c)) {}
  // The numeric constructors matter: without them, String(someInt) would bind
  // to String(char) and silently yield a one-character string. That is exactly
  // what Improv scan results would have done with an int32_t RSSI, so they are
  // deliberately faithful to Arduino rather than "good enough".
  String(int value) : std::string(std::to_string(value)) {}
  String(unsigned int value) : std::string(std::to_string(value)) {}
  String(long value) : std::string(std::to_string(value)) {}
  String(unsigned long value) : std::string(std::to_string(value)) {}
  String(unsigned char value, int base) : std::string(host_detail::encodeUnsigned(value, base)) {}

  long toInt() const { return strtol(c_str(), nullptr, 10); }
  float toFloat() const { return strtof(c_str(), nullptr); }
  bool equals(const String& o) const { return *this == static_cast<const std::string&>(o); }
  void trim() {}
  int compareTo(const String& o) const { return compare(o.c_str()); }
  void toUpperCase() {
    for (char& c : *this) {
      if (c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
    }
  }
  void replace(const String& find, const String& with) {
    if (find.empty()) return;
    size_t pos = 0;
    // Qualified: this member hides every std::string::replace overload.
    while ((pos = std::string::find(find.c_str(), pos)) != std::string::npos) {
      std::string::replace(pos, find.size(), static_cast<const std::string&>(with));
      pos += with.size();
    }
  }

  bool startsWith(const String& p) const {
    return compare(0, p.size(), p.c_str(), 0, p.size()) == 0;
  }
  bool endsWith(const String& p) const {
    if (p.size() > size()) return false;
    return compare(size() - p.size(), p.size(), p.c_str(), 0, p.size()) == 0;
  }
  int indexOf(char c, int from = 0) const {
    auto pos = find(c, static_cast<size_t>(from));
    return pos == std::string::npos ? -1 : static_cast<int>(pos);
  }
  int indexOf(const String& p) const {
    auto pos = find(p.c_str());
    return pos == std::string::npos ? -1 : static_cast<int>(pos);
  }
  String substring(int from) const { return String(substr(from < 0 ? 0 : from)); }
  String substring(int from, int to) const {
    if (from < 0) from = 0;
    if (to < from) return String();
    return String(substr(from, static_cast<size_t>(to - from)));
  }
};

class Stream {
 public:
  virtual ~Stream() = default;
  virtual int available() { return 0; }
  virtual int read() { return -1; }
  virtual int peek() { return -1; }
  virtual size_t readBytes(uint8_t*, size_t) { return 0; }
  virtual void flush() {}
  virtual size_t write(uint8_t) { return 1; }
  virtual size_t write(const uint8_t*, size_t n) { return n; }
};

class HardwareSerial : public Stream {
 public:
  template <typename... A> size_t print(A&&...) { return 0; }
  template <typename... A> size_t println(A&&...) { return 0; }
  void begin(unsigned long) {}
  void end() {}
  void setTimeout(unsigned long) {}
};

extern HardwareSerial Serial;
