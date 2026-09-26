#pragma once
// Minimal Preferences host shim — NOT the ESP32 NVS Preferences.
//
// Why: test/test_provisioning exercises config/ConfigStore.h, whose ESP32 path
// is built on <Preferences.h>. The real class is an esp-idf NVS binding; on a
// host it only has to behave like a namespaced key/value store that survives
// between instances within one process, which is all
// ConfigStore::load()/save() and the round-trip test need.
//
// This is a test scaffold only. It must never be on the include path for a
// real firmware build — src/config/ConfigStore.cpp includes <Preferences.h> by
// that exact name, so if this file ever shadowed the core's header it would
// silently replace NVS with a RAM map on hardware. Only
// scripts/run-host-tests.sh puts test/host on the include path.

#include <cstdint>
#include <map>
#include <string>

#include <Arduino.h>  // String

class Preferences {
 public:
  // Returns true when the namespace is usable. The real class returns false
  // when the NVS partition cannot be opened; a host map always can, so
  // ConfigStore::begin() is unconditionally true here.
  bool begin(const char* name, bool readOnly = false) {
    (void)readOnly;
    namespace_ = name != nullptr ? name : "";
    return true;
  }

  void end() { namespace_.clear(); }

  String getString(const char* key, const String& defaultValue = "") {
    const auto it = store_.find(keyOf(key));
    return it == store_.end() ? defaultValue : String(it->second);
  }

  size_t putString(const char* key, const String& value) {
    store_[keyOf(key)] = static_cast<const std::string&>(value);
    // Arduino returns the stored byte count including the length prefix, so
    // even an empty string is a success (> 0). ConfigStore::save() relies on
    // that to distinguish "written" from "failed".
    return value.length() + 1;
  }

  uint32_t getUInt(const char* key, uint32_t defaultValue = 0) {
    const auto it = store_.find(keyOf(key));
    return it == store_.end() ? defaultValue : static_cast<uint32_t>(std::stoul(it->second));
  }

  size_t putUInt(const char* key, uint32_t value) {
    store_[keyOf(key)] = std::to_string(value);
    return sizeof(uint32_t);
  }

  int32_t getInt(const char* key, int32_t defaultValue = 0) {
    const auto it = store_.find(keyOf(key));
    return it == store_.end() ? defaultValue : static_cast<int32_t>(std::stol(it->second));
  }

  size_t putInt(const char* key, int32_t value) {
    store_[keyOf(key)] = std::to_string(value);
    return sizeof(int32_t);
  }

  bool getBool(const char* key, bool defaultValue = false) {
    const auto it = store_.find(keyOf(key));
    return it == store_.end() ? defaultValue : it->second != "0";
  }

  size_t putBool(const char* key, bool value) {
    store_[keyOf(key)] = value ? "1" : "0";
    return sizeof(bool);
  }

 private:
  std::string keyOf(const char* key) const { return namespace_ + "/" + (key != nullptr ? key : ""); }

  // Namespace-qualified so a test that opens two namespaces cannot see the
  // other's keys, matching NVS.
  static inline std::map<std::string, std::string> store_;
  std::string namespace_;
};
