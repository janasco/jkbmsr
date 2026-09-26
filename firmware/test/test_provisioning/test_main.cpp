#include <Arduino.h>
#include <unity.h>

#include <vector>

#include "config/ConfigStore.h"
#include "device/DeviceIdentity.h"
#include "provisioning/CaptivePortal.h"
#include "provisioning/ImprovProtocol.h"
#include "provisioning/ProvisioningManager.h"
#include "provisioning/ResetTrigger.h"

using namespace jkbmsr;
using improv::Command;
using improv::Error;
using improv::PacketType;
using improv::State;

namespace {

// In-memory Stream used to drive ProvisioningManager without USB hardware.
class FakeStream : public Stream {
 public:
  size_t write(uint8_t byte) override {
    tx_.push_back(byte);
    return 1;
  }

  size_t write(const uint8_t* buffer, size_t size) override {
    for (size_t i = 0; i < size; ++i) {
      tx_.push_back(buffer[i]);
    }
    return size;
  }

  int available() override { return static_cast<int>(rx_.size()); }

  int read() override {
    if (rx_.empty()) {
      return -1;
    }
    const int value = rx_.front();
    rx_.erase(rx_.begin());
    return value;
  }

  int peek() override { return rx_.empty() ? -1 : rx_.front(); }

  void flush() override {}

  void inject(const uint8_t* data, size_t length) {
    for (size_t i = 0; i < length; ++i) {
      rx_.push_back(data[i]);
    }
  }

  void clearTx() { tx_.clear(); }

  const std::vector<uint8_t>& tx() const { return tx_; }

 private:
  std::vector<uint8_t> rx_;
  std::vector<uint8_t> tx_;
};

void buildWifiSettingsPacket(const String& ssid, const String& password, std::vector<uint8_t>& out) {
  const uint8_t ssidLen = static_cast<uint8_t>(ssid.length());
  const uint8_t passLen = static_cast<uint8_t>(password.length());
  const uint8_t cmdLen = static_cast<uint8_t>(1 + ssidLen + 1 + passLen);

  uint8_t rpc[improv::kMaxData];
  size_t pos = 0;
  rpc[pos++] = static_cast<uint8_t>(Command::WifiSettings);
  rpc[pos++] = cmdLen;
  rpc[pos++] = ssidLen;
  for (uint8_t i = 0; i < ssidLen; ++i) {
    rpc[pos++] = static_cast<uint8_t>(ssid[i]);
  }
  rpc[pos++] = passLen;
  for (uint8_t i = 0; i < passLen; ++i) {
    rpc[pos++] = static_cast<uint8_t>(password[i]);
  }

  uint8_t packet[improv::kMaxData + 16];
  const size_t written =
      improv::buildPacket(PacketType::RpcCommand, rpc, static_cast<uint8_t>(pos), packet);
  out.assign(packet, packet + written);
}

void buildDeviceInfoPacket(std::vector<uint8_t>& out) {
  const uint8_t rpc[] = {static_cast<uint8_t>(Command::RequestDeviceInfo), 0};
  uint8_t packet[improv::kMaxData + 16];
  const size_t written = improv::buildPacket(PacketType::RpcCommand, rpc, sizeof(rpc), packet);
  out.assign(packet, packet + written);
}

void buildScanPacket(std::vector<uint8_t>& out) {
  const uint8_t rpc[] = {static_cast<uint8_t>(Command::RequestScan), 0};
  uint8_t packet[improv::kMaxData + 16];
  const size_t written = improv::buildPacket(PacketType::RpcCommand, rpc, sizeof(rpc), packet);
  out.assign(packet, packet + written);
}

size_t countRpcResults(const std::vector<uint8_t>& tx, Command command, bool emptyOnly = false) {
  improv::Parser parser;
  size_t count = 0;
  for (uint8_t byte : tx) {
    if (!parser.feed(byte) || parser.type() != PacketType::RpcResult || parser.length() < 2) continue;
    const uint8_t* data = parser.data();
    if (data[0] == static_cast<uint8_t>(command) && (!emptyOnly || data[1] == 0)) ++count;
  }
  return count;
}

bool txContainsState(const std::vector<uint8_t>& tx, State state) {
  // Current-state packets: IMPROV + ver + type(0x01) + len(1) + state + checksum
  for (size_t i = 0; i + 10 < tx.size(); ++i) {
    if (tx[i] == 'I' && tx[i + 1] == 'M' && tx[i + 2] == 'P' && tx[i + 3] == 'R' &&
        tx[i + 4] == 'O' && tx[i + 5] == 'V' && tx[i + 7] == 0x01 && tx[i + 8] == 0x01 &&
        tx[i + 9] == static_cast<uint8_t>(state)) {
      return true;
    }
  }
  return false;
}

bool txContainsError(const std::vector<uint8_t>& tx, Error error) {
  for (size_t i = 0; i + 10 < tx.size(); ++i) {
    if (tx[i] == 'I' && tx[i + 1] == 'M' && tx[i + 2] == 'P' && tx[i + 3] == 'R' &&
        tx[i + 4] == 'O' && tx[i + 5] == 'V' && tx[i + 7] == 0x02 && tx[i + 8] == 0x01 &&
        tx[i + 9] == static_cast<uint8_t>(error)) {
      return true;
    }
  }
  return false;
}

constexpr const char kClaimAlphabet[] = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

bool claimCodeCharValid(char c) {
  for (size_t i = 0; kClaimAlphabet[i] != '\0'; ++i) {
    if (kClaimAlphabet[i] == c) {
      return true;
    }
  }
  return false;
}

}  // namespace

void test_wifi_configured_helper() {
  DeviceConfig config;
  TEST_ASSERT_FALSE(config.wifiConfigured());
  config.wifiSsid = "home";
  TEST_ASSERT_TRUE(config.wifiConfigured());
  config.wifiSsid = "";
  TEST_ASSERT_FALSE(config.wifiConfigured());
}

void test_build_onboard_url() {
  const String url = buildOnboardUrl("jkbmsr-deadbeef", "ABCD2345");
  // web.jkbmsr.com, not the app.jkbmsr.com these suites used to expect: the
  // platform split retired the latter (see commit 7ca1737, "point onboarding
  // URL at web.jkbmsr.com"). The suite only caught up when the host runner
  // finally executed it, since CI had only ever compiled it.
  TEST_ASSERT_EQUAL_STRING(
      "https://web.jkbmsr.com/onboard?device=jkbmsr-deadbeef&code=ABCD2345",
      url.c_str());
}

void test_soft_ap_ssid_uses_last_four() {
  TEST_ASSERT_EQUAL_STRING(
      "JKBMSR-Setup-CDEF",
      CaptivePortal::softApSsid("jkbmsr-abcdef").c_str());
  TEST_ASSERT_EQUAL_STRING("JKBMSR-Setup-AB", CaptivePortal::softApSsid("ab").c_str());
}

// The SoftAP password is no longer a documented global constant. It is derived
// per device from the claim code, so these tests pin the properties that
// actually matter: it is a valid WPA2 passphrase length, it is stable for the
// same device, it differs between devices, and it no longer accepts the old
// published value.
void test_soft_ap_password_is_per_device() {
  const String a = CaptivePortal::softApPassword("jkbmsr-abcdef", "ABCD2345");
  const String b = CaptivePortal::softApPassword("jkbmsr-abcdef", "ABCD2345");
  const String c = CaptivePortal::softApPassword("jkbmsr-999999", "ABCD2345");
  const String d = CaptivePortal::softApPassword("jkbmsr-abcdef", "ZZZZ9999");

  // Deterministic, so a user can rejoin after a reflash using the printed
  // claim code.
  TEST_ASSERT_EQUAL_STRING(a.c_str(), b.c_str());
  // Distinct per device...
  TEST_ASSERT_TRUE(a != c);
  // ...and distinct per claim code.
  TEST_ASSERT_TRUE(a != d);
  // The old published constant must never come back.
  TEST_ASSERT_TRUE(a != "123456789");
}

void test_soft_ap_password_is_a_valid_wpa2_passphrase() {
  const String p = CaptivePortal::softApPassword("jkbmsr-abcdef", "ABCD2345");
  // WPA2 requires 8..63 characters.
  TEST_ASSERT_TRUE(p.length() >= 8);
  TEST_ASSERT_TRUE(p.length() <= 63);
  // Must be in the claim code's ambiguity-free alphabet so it can be read off
  // a serial log without ambiguity (no 0/O/1/I/L).
  for (size_t i = 0; i < p.length(); ++i) {
    TEST_ASSERT_TRUE(claimCodeCharValid(p[i]));
  }
}

void test_claim_code_length_and_alphabet() {
  DeviceIdentity identity;
  const String code = identity.generateClaimCode();
  TEST_ASSERT_EQUAL_UINT(8, code.length());
  for (size_t i = 0; i < code.length(); ++i) {
    TEST_ASSERT_TRUE(claimCodeCharValid(code[i]));
  }
}

void test_claim_code_non_repeating() {
  DeviceIdentity identity;
  String previous;
  int distinct = 0;
  for (int i = 0; i < 8; ++i) {
    const String code = identity.generateClaimCode();
    if (code != previous) {
      distinct++;
    }
    previous = code;
  }
  // 8 draws of 40 bits each colliding every time is effectively impossible.
  TEST_ASSERT_TRUE(distinct >= 2);
}

void test_config_store_claim_code_round_trip() {
  ConfigStore store;
  TEST_ASSERT_TRUE(store.begin());

  DeviceConfig original = store.load();
  const String savedDeviceId = original.deviceId;
  const String savedClaim = original.claimCode;
  const String savedSsid = original.wifiSsid;

  original.deviceId = "jkbmsr-test-device";
  original.claimCode = "TESTCODE";
  original.wifiSsid = "roundtrip-ssid";
  TEST_ASSERT_TRUE(store.save(original));

  DeviceConfig loaded = store.load();
  TEST_ASSERT_EQUAL_STRING("jkbmsr-test-device", loaded.deviceId.c_str());
  TEST_ASSERT_EQUAL_STRING("TESTCODE", loaded.claimCode.c_str());
  TEST_ASSERT_EQUAL_STRING("roundtrip-ssid", loaded.wifiSsid.c_str());
  TEST_ASSERT_TRUE(loaded.wifiConfigured());

  // Restore prior NVS contents so a hardware test run is not destructive.
  original.deviceId = savedDeviceId;
  original.claimCode = savedClaim;
  original.wifiSsid = savedSsid;
  store.save(original);
}

void test_provisioning_success_path() {
  FakeStream stream;
  ProvisioningManager manager;
  manager.begin(stream, "jkbmsr-dev1", "CLAIM001");

  String ssid;
  String password;
  // Announce Ready.
  TEST_ASSERT_FALSE(manager.poll([](const String&, const String&) { return false; }, ssid, password));
  TEST_ASSERT_EQUAL(static_cast<int>(State::Ready), static_cast<int>(manager.state()));
  TEST_ASSERT_TRUE(txContainsState(stream.tx(), State::Ready));

  std::vector<uint8_t> packet;
  buildWifiSettingsPacket("MyNet", "secret", packet);
  stream.clearTx();
  stream.inject(packet.data(), packet.size());

  bool connectCalled = false;
  const bool done = manager.poll(
      [&](const String& s, const String& p) {
        connectCalled = true;
        TEST_ASSERT_EQUAL_STRING("MyNet", s.c_str());
        TEST_ASSERT_EQUAL_STRING("secret", p.c_str());
        return true;
      },
      ssid, password);

  TEST_ASSERT_TRUE(connectCalled);
  TEST_ASSERT_TRUE(done);
  TEST_ASSERT_EQUAL_STRING("MyNet", ssid.c_str());
  TEST_ASSERT_EQUAL_STRING("secret", password.c_str());
  TEST_ASSERT_EQUAL(static_cast<int>(State::Provisioned), static_cast<int>(manager.state()));
  TEST_ASSERT_TRUE(txContainsState(stream.tx(), State::Provisioning));
  TEST_ASSERT_TRUE(txContainsState(stream.tx(), State::Provisioned));

  // Redirect URL must appear in the RPC result payload.
  const String expectedUrl = buildOnboardUrl("jkbmsr-dev1", "CLAIM001");
  String txAsString;
  for (uint8_t b : stream.tx()) {
    txAsString += static_cast<char>(b);
  }
  TEST_ASSERT_TRUE(txAsString.indexOf(expectedUrl) >= 0);
}

void test_provisioning_error_retry_path() {
  FakeStream stream;
  ProvisioningManager manager;
  manager.begin(stream, "jkbmsr-dev2", "CLAIM002");

  String ssid;
  String password;
  manager.poll([](const String&, const String&) { return false; }, ssid, password);

  std::vector<uint8_t> packet;
  buildWifiSettingsPacket("BadNet", "wrong", packet);
  stream.clearTx();
  stream.inject(packet.data(), packet.size());

  const bool done = manager.poll(
      [](const String&, const String&) { return false; },
      ssid, password);

  TEST_ASSERT_FALSE(done);
  TEST_ASSERT_EQUAL(static_cast<int>(State::Ready), static_cast<int>(manager.state()));
  TEST_ASSERT_TRUE(txContainsState(stream.tx(), State::Provisioning));
  TEST_ASSERT_TRUE(txContainsError(stream.tx(), Error::UnableToConnect));
  TEST_ASSERT_TRUE(txContainsState(stream.tx(), State::Ready));

  // Retry with good credentials after the failure.
  buildWifiSettingsPacket("GoodNet", "ok", packet);
  stream.clearTx();
  stream.inject(packet.data(), packet.size());
  const bool retryDone = manager.poll(
      [](const String& s, const String&) { return s == "GoodNet"; },
      ssid, password);
  TEST_ASSERT_TRUE(retryDone);
  TEST_ASSERT_EQUAL_STRING("GoodNet", ssid.c_str());
  TEST_ASSERT_EQUAL(static_cast<int>(State::Provisioned), static_cast<int>(manager.state()));
}

void test_open_wifi_network_accepts_empty_password() {
  FakeStream stream;
  ProvisioningManager manager;
  manager.begin(stream, "jkbmsr-open", "OPEN1234");

  std::vector<uint8_t> packet;
  buildWifiSettingsPacket("CommunityWiFi", "", packet);
  stream.inject(packet.data(), packet.size());
  String ssid;
  String password;
  const bool done = manager.poll(
      [](const String& candidateSsid, const String& candidatePassword) {
        return candidateSsid == "CommunityWiFi" && candidatePassword.length() == 0;
      },
      ssid, password);

  TEST_ASSERT_TRUE(done);
  TEST_ASSERT_EQUAL_STRING("CommunityWiFi", ssid.c_str());
  TEST_ASSERT_EQUAL_UINT32(0, password.length());
}

void test_wifi_scan_returns_networks_and_terminator() {
  FakeStream stream;
  ProvisioningManager manager;
  manager.begin(stream, "jkbmsr-scan", "SCAN1234", false);

  std::vector<uint8_t> packet;
  buildScanPacket(packet);
  stream.inject(packet.data(), packet.size());
  String ssid;
  String password;
  TEST_ASSERT_FALSE(manager.poll(
      {}, ssid, password,
      [](ProvisioningManager::Network* networks, size_t capacity) {
        TEST_ASSERT_GREATER_OR_EQUAL_UINT32(2, capacity);
        networks[0].ssid = "Workshop";
        networks[0].rssi = -41;
        networks[0].secure = true;
        networks[1].ssid = "Guest";
        networks[1].rssi = -67;
        networks[1].secure = false;
        return static_cast<size_t>(2);
      }));

  String response;
  for (uint8_t byte : stream.tx()) response += static_cast<char>(byte);
  TEST_ASSERT_TRUE(response.indexOf("Workshop") >= 0);
  TEST_ASSERT_TRUE(response.indexOf("Guest") >= 0);
  TEST_ASSERT_TRUE(response.indexOf("-41") >= 0);
  TEST_ASSERT_TRUE(response.indexOf("YES") >= 0);
  TEST_ASSERT_TRUE(response.indexOf("NO") >= 0);
  TEST_ASSERT_EQUAL_UINT32(3, countRpcResults(stream.tx(), Command::RequestScan));
  TEST_ASSERT_EQUAL_UINT32(1, countRpcResults(stream.tx(), Command::RequestScan, true));
}

void test_identity_discovery_for_already_connected_gateway() {
  FakeStream stream;
  ProvisioningManager manager;
  manager.begin(stream, "jkbmsr-existing", "OWNER123", false, true);

  std::vector<uint8_t> packet;
  buildDeviceInfoPacket(packet);
  stream.inject(packet.data(), packet.size());
  String ssid;
  String password;
  TEST_ASSERT_FALSE(manager.poll({}, ssid, password));
  TEST_ASSERT_FALSE(txContainsState(stream.tx(), State::Ready));

  String response;
  for (uint8_t byte : stream.tx()) {
    response += static_cast<char>(byte);
  }
  TEST_ASSERT_TRUE(response.indexOf("https://web.jkbmsr.com/onboard?device=jkbmsr-existing&code=OWNER123") >= 0);
  TEST_ASSERT_TRUE(response.indexOf("claim-ready") >= 0);
}

void test_reset_trigger_constants() {
  // Documented hold windows from the Phase 1 spec.
  TEST_ASSERT_EQUAL_UINT32(5000, ResetTrigger::kSoftHoldMs);
  TEST_ASSERT_EQUAL_UINT32(10000, ResetTrigger::kFactoryHoldMs);
  TEST_ASSERT_EQUAL_UINT8(0, ResetTrigger::kDefaultPin);
}

void setup() {
  delay(200);
  UNITY_BEGIN();
  RUN_TEST(test_wifi_configured_helper);
  RUN_TEST(test_build_onboard_url);
  RUN_TEST(test_soft_ap_ssid_uses_last_four);
  RUN_TEST(test_soft_ap_password_is_per_device);
  RUN_TEST(test_soft_ap_password_is_a_valid_wpa2_passphrase);
  RUN_TEST(test_claim_code_length_and_alphabet);
  RUN_TEST(test_claim_code_non_repeating);
  RUN_TEST(test_config_store_claim_code_round_trip);
  RUN_TEST(test_provisioning_success_path);
  RUN_TEST(test_provisioning_error_retry_path);
  RUN_TEST(test_open_wifi_network_accepts_empty_password);
  RUN_TEST(test_wifi_scan_returns_networks_and_terminator);
  RUN_TEST(test_identity_discovery_for_already_connected_gateway);
  RUN_TEST(test_reset_trigger_constants);
  UNITY_END();
}

void loop() {}
