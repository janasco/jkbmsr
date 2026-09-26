#pragma once
// Minimal LittleFS host shim — NOT the ESP8266 LittleFS filesystem.
//
// Why it exists: config/ConfigStore.cpp has a second implementation selected by
// ARDUINO_ARCH_ESP8266 that persists the config as JSON through LittleFS. The
// ESP32 build never reaches that branch, so run-host-tests.sh compiles the
// Preferences branch instead; this file provides (and documents) the LittleFS
// surface the other branch needs so it is a known quantity rather than a
// surprise.
//
// It is NOT exercised today: selecting the ESP8266 branch also needs ArduinoJson
// (JsonDocument/serializeJson/deserializeJson), which is deliberately not
// stubbed. Nothing in the host run may start depending on this being complete.
//
// This is a test scaffold only. It must never be on the include path for a real
// firmware build.

#include <cstdint>
#include <map>
#include <memory>
#include <string>

#include <Arduino.h>  // String, Stream

// Open file handle. ArduinoJson's deserializeJson()/serializeJson() want a
// Stream, so deriving from Stream is the part that actually matters if this
// branch is ever enabled. The handle shares storage with LittleFSClass, so what
// one handle writes another handle can read back.
class LittleFSFile : public Stream {
 public:
  explicit LittleFSFile(std::shared_ptr<std::string> storage) : storage_(std::move(storage)) {}
  ~LittleFSFile() override = default;

  // Arduino's `if (!file)` test for a failed open.
  operator bool() const { return storage_ != nullptr; }

  void close() { storage_.reset(); }
  void flush() {}

  int available() override { return storage_ ? static_cast<int>(storage_->size()) : 0; }
  int read() override {
    if (!storage_ || storage_->empty()) return -1;
    const char byte = storage_->front();
    storage_->erase(storage_->begin());
    return static_cast<uint8_t>(byte);
  }
  int peek() override { return (!storage_ || storage_->empty()) ? -1 : static_cast<uint8_t>(storage_->front()); }
  size_t write(uint8_t byte) override {
    if (!storage_) return 0;
    storage_->push_back(static_cast<char>(byte));
    return 1;
  }
  size_t write(const uint8_t* buffer, size_t size) override {
    if (!storage_) return 0;
    for (size_t i = 0; i < size; ++i) storage_->push_back(static_cast<char>(buffer[i]));
    return size;
  }

 private:
  std::shared_ptr<std::string> storage_;
};

class LittleFSClass {
 public:
  bool begin() { return true; }

  LittleFSFile open(const char* path, const char* mode = "r") {
    const std::string key = path != nullptr ? path : "";
    if (mode != nullptr && mode[0] == 'w') {
      // "w" truncates, and creates the file if it is not there yet.
      return LittleFSFile(files_[key] = std::make_shared<std::string>());
    }
    auto it = files_.find(key);
    if (it == files_.end()) {
      return LittleFSFile(nullptr);  // failed open
    }
    return LittleFSFile(it->second);
  }

  bool remove(const char* path) { return files_.erase(path != nullptr ? path : "") == 1; }

  bool rename(const char* from, const char* to) {
    auto it = files_.find(from != nullptr ? from : "");
    if (it == files_.end()) return false;
    files_[to != nullptr ? to : ""] = it->second;
    files_.erase(it);
    return true;
  }

 private:
  static inline std::map<std::string, std::shared_ptr<std::string>> files_;
};

// Arduino exposes the filesystem as a global object, not a class to construct.
inline LittleFSClass LittleFS;
