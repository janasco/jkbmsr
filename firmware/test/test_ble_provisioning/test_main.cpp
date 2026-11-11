// The provisioning core, without a radio.
//
// Three pieces decide whether a gateway ends up on the right network and the
// right account: the chunk buffer (a half-written payload must never look
// complete), field validation (all or nothing), and the session (no credential
// write before the per-boot setup code). The radio is verified on hardware; this
// suite is what makes the logic trustable before it gets there.

#include <Arduino.h>
#include <unity.h>

#include "cloud/ProvisioningPayload.h"
#include "cloud/ProvisioningSession.h"

using namespace jkbmsr;

namespace {

void writeAscii(ProvisioningBuffer& buffer, uint16_t offset, const char* text) {
  buffer.write(offset, reinterpret_cast<const uint8_t*>(text), strlen(text));
}

ProvisioningCredentials validCredentials() {
  ProvisioningCredentials credentials;
  credentials.ssid = "HouseWiFi";
  credentials.password = "correct horse battery";
  credentials.timeZone = "PST-8";
  credentials.claimToken = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature";
  return credentials;
}

}  // namespace

// --- the chunk buffer -------------------------------------------------------

void test_sequential_chunks_assemble_and_complete() {
  ProvisioningBuffer buffer;
  writeAscii(buffer, 0, "{\"ssid\":\"A\"}");
  writeAscii(buffer, 12, "");
  buffer.reset();
  writeAscii(buffer, 0, "{\"ssid\":\"A\",");
  writeAscii(buffer, 12, "\"password\":\"x\"}");
  // 12 + 15: the first chunk ends after the comma, the second carries the rest.
  TEST_ASSERT_EQUAL_UINT32(27, buffer.length());
  TEST_ASSERT_TRUE(buffer.complete());
  TEST_ASSERT_EQUAL_STRING("{\"ssid\":\"A\",\"password\":\"x\"}", reinterpret_cast<const char*>(buffer.data()));
}

void test_out_of_order_chunks_assemble_and_complete() {
  ProvisioningBuffer buffer;
  writeAscii(buffer, 12, "\"password\":\"x\"}");
  writeAscii(buffer, 0, "{\"ssid\":\"A\",");
  TEST_ASSERT_TRUE(buffer.complete());
  TEST_ASSERT_EQUAL_STRING("{\"ssid\":\"A\",\"password\":\"x\"}", reinterpret_cast<const char*>(buffer.data()));
}

void test_a_gap_is_not_complete() {
  ProvisioningBuffer buffer;
  writeAscii(buffer, 0, "{\"ssid\":");
  writeAscii(buffer, 20, "\"}");
  TEST_ASSERT_EQUAL_UINT32(22, buffer.length());
  TEST_ASSERT_FALSE(buffer.complete());
}

void test_overlap_is_refused_rather_than_overwritten() {
  ProvisioningBuffer buffer;
  TEST_ASSERT_TRUE(buffer.write(0, reinterpret_cast<const uint8_t*>("aaaa"), 4));
  // A second writer disagreeing about a byte is a transport bug. Refusing it is
  // what keeps the first value intact and makes the bug visible.
  TEST_ASSERT_FALSE(buffer.write(2, reinterpret_cast<const uint8_t*>("bb"), 2));
  TEST_ASSERT_EQUAL_STRING("aaaa", reinterpret_cast<const char*>(buffer.data()));
}

void test_a_chunk_past_capacity_is_refused() {
  ProvisioningBuffer buffer;
  const uint8_t byte = 'x';
  TEST_ASSERT_TRUE(buffer.write(ProvisioningBuffer::kCapacity - 1, &byte, 1));
  TEST_ASSERT_FALSE(buffer.write(ProvisioningBuffer::kCapacity - 1, &byte, 2));
  TEST_ASSERT_FALSE(buffer.write(ProvisioningBuffer::kCapacity, &byte, 1));
}

void test_an_empty_chunk_is_refused() {
  ProvisioningBuffer buffer;
  TEST_ASSERT_FALSE(buffer.write(0, nullptr, 0));
  TEST_ASSERT_FALSE(buffer.complete());
}

void test_reset_clears_both_the_bytes_and_the_coverage() {
  ProvisioningBuffer buffer;
  writeAscii(buffer, 0, "hello");
  buffer.reset();
  TEST_ASSERT_FALSE(buffer.complete());
  TEST_ASSERT_EQUAL_UINT32(0, buffer.length());
  // The same offset is writable again only because coverage was cleared.
  TEST_ASSERT_TRUE(buffer.write(0, reinterpret_cast<const uint8_t*>("bye"), 3));
}

// --- validation -------------------------------------------------------------

void test_valid_credentials_pass() {
  TEST_ASSERT_EQUAL_INT(static_cast<int>(CredentialError::none),
                        static_cast<int>(validateProvisioningCredentials(validCredentials())));
}

void test_an_open_network_is_allowed() {
  ProvisioningCredentials credentials = validCredentials();
  credentials.password = "";
  TEST_ASSERT_EQUAL_INT(static_cast<int>(CredentialError::none),
                        static_cast<int>(validateProvisioningCredentials(credentials)));
}

void test_each_bad_field_is_named() {
  {
    ProvisioningCredentials c = validCredentials();
    c.ssid = "";
    TEST_ASSERT_EQUAL_STRING("ssid", credentialErrorName(validateProvisioningCredentials(c)));
  }
  {
    ProvisioningCredentials c = validCredentials();
    c.ssid = String("0123456789012345678901234567890123");  // 34 bytes
    TEST_ASSERT_EQUAL_STRING("ssid", credentialErrorName(validateProvisioningCredentials(c)));
  }
  {
    ProvisioningCredentials c = validCredentials();
    // A 64-char passphrase. Built by appending because the host shim's
    // String(count, char) is the numeric base constructor, not a repeat.
    String longPassword;
    for (int i = 0; i < 64; ++i) {
      longPassword += 'p';
    }
    c.password = longPassword;
    TEST_ASSERT_EQUAL_STRING("password", credentialErrorName(validateProvisioningCredentials(c)));
  }
  {
    // An IANA name is the mistake a human makes; the ESP32 has no tz database.
    ProvisioningCredentials c = validCredentials();
    c.timeZone = "Asia/Manila";
    TEST_ASSERT_EQUAL_STRING("timezone", credentialErrorName(validateProvisioningCredentials(c)));
  }
  {
    ProvisioningCredentials c = validCredentials();
    c.claimToken = "";
    TEST_ASSERT_EQUAL_STRING("token", credentialErrorName(validateProvisioningCredentials(c)));
  }
  {
    ProvisioningCredentials c = validCredentials();
    c.claimToken = "not-a-jwt";
    TEST_ASSERT_EQUAL_STRING("token", credentialErrorName(validateProvisioningCredentials(c)));
  }
  {
    ProvisioningCredentials c = validCredentials();
    c.claimToken = "aa.bb.";  // empty third segment
    TEST_ASSERT_EQUAL_STRING("token", credentialErrorName(validateProvisioningCredentials(c)));
  }
}

void test_the_setup_code_is_always_six_digits() {
  TEST_ASSERT_EQUAL_STRING("000302", formatSetupCode(302).c_str());
  TEST_ASSERT_EQUAL_STRING("418302", formatSetupCode(418302).c_str());
  TEST_ASSERT_EQUAL_STRING("000000", formatSetupCode(1000000).c_str());  // wraps, stays six
}

// --- the session ------------------------------------------------------------

void test_no_credentials_before_the_setup_code() {
  ProvisioningSession session("418302");
  TEST_ASSERT_FALSE(session.credentialsWritable());
  TEST_ASSERT_FALSE(session.commit(0));
  TEST_ASSERT_TRUE(session.onConnected(0));
  TEST_ASSERT_FALSE(session.credentialsWritable());
}

void test_three_wrong_codes_lock_the_connection_out() {
  ProvisioningSession session("418302");
  TEST_ASSERT_TRUE(session.onConnected(0));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SetupCodeResult::rejected),
                        static_cast<int>(session.submitSetupCode("000000", 10)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SetupCodeResult::rejected),
                        static_cast<int>(session.submitSetupCode("418301", 20)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SetupCodeResult::lockedOut),
                        static_cast<int>(session.submitSetupCode("123456", 30)));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(ProvisioningState::advertising),
                        static_cast<int>(session.state()));
  TEST_ASSERT_FALSE(session.credentialsWritable());
}

void test_a_correct_code_opens_the_window() {
  ProvisioningSession session("418302");
  session.onConnected(0);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(SetupCodeResult::accepted),
                        static_cast<int>(session.submitSetupCode("418302", 1000)));
  TEST_ASSERT_TRUE(session.credentialsWritable());
  TEST_ASSERT_TRUE(session.commit(2000));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(ProvisioningState::applying),
                        static_cast<int>(session.state()));
}

void test_the_window_closes_after_sixty_seconds() {
  ProvisioningSession session("418302");
  session.onConnected(0);
  session.submitSetupCode("418302", 0);
  TEST_ASSERT_FALSE(session.commit(ProvisioningSession::kAuthTimeoutMs + 1));
  TEST_ASSERT_FALSE(session.credentialsWritable());
}

void test_a_second_phone_is_refused_while_one_is_connected() {
  ProvisioningSession session("418302");
  TEST_ASSERT_TRUE(session.onConnected(0));
  TEST_ASSERT_FALSE(session.onConnected(10));
}

void test_a_disconnect_returns_to_advertising() {
  ProvisioningSession session("418302");
  session.onConnected(0);
  session.submitSetupCode("418302", 0);
  session.onDisconnected();
  TEST_ASSERT_EQUAL_INT(static_cast<int>(ProvisioningState::advertising),
                        static_cast<int>(session.state()));
  TEST_ASSERT_FALSE(session.credentialsWritable());
}

void test_an_idle_connection_is_dropped() {
  ProvisioningSession session("418302");
  session.onConnected(0);
  TEST_ASSERT_FALSE(session.tick(ProvisioningSession::kIdleTimeoutMs));
  TEST_ASSERT_TRUE(session.tick(ProvisioningSession::kIdleTimeoutMs + 1));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(ProvisioningState::advertising),
                        static_cast<int>(session.state()));
}

void test_the_happy_path_reaches_running() {
  ProvisioningSession session("418302");
  session.onConnected(0);
  session.submitSetupCode("418302", 0);
  TEST_ASSERT_TRUE(session.commit(1000));
  TEST_ASSERT_TRUE(session.onStored());
  TEST_ASSERT_TRUE(session.onRebootComplete());
  TEST_ASSERT_TRUE(session.onRegistered());
  TEST_ASSERT_EQUAL_INT(static_cast<int>(ProvisioningState::running),
                        static_cast<int>(session.state()));
}

void test_steps_out_of_order_are_refused() {
  ProvisioningSession session("418302");
  TEST_ASSERT_FALSE(session.onStored());
  TEST_ASSERT_FALSE(session.onRegistered());
  session.onConnected(0);
  session.submitSetupCode("418302", 0);
  // Skipping apply is a bug in the caller, and it must not look successful.
  TEST_ASSERT_FALSE(session.onStored());
}

void test_a_failure_carries_a_reason() {
  ProvisioningSession session("418302");
  session.onConnected(0);
  session.submitSetupCode("418302", 0);
  session.fail("storage");
  TEST_ASSERT_EQUAL_INT(static_cast<int>(ProvisioningState::failed),
                        static_cast<int>(session.state()));
  TEST_ASSERT_EQUAL_STRING("storage", session.errorReason().c_str());
}

// --- the advertising policy ------------------------------------------------

void test_an_unconfigured_gateway_advertises_immediately() {
  TEST_ASSERT_TRUE(shouldAdvertiseProvisioning(false, false, 0));
}

void test_a_running_gateway_never_advertises() {
  TEST_ASSERT_FALSE(shouldAdvertiseProvisioning(true, true, 0));
  TEST_ASSERT_FALSE(shouldAdvertiseProvisioning(true, true, 10 * 60000));
}

void test_a_short_wifi_blip_does_not_open_provisioning() {
  // Jamming a 2.4 GHz network is easy; without the grace the window could be
  // forced open and the device provisioned by whoever did it.
  TEST_ASSERT_FALSE(shouldAdvertiseProvisioning(true, false, 2000));
  TEST_ASSERT_FALSE(shouldAdvertiseProvisioning(true, false, 59000));
  TEST_ASSERT_TRUE(shouldAdvertiseProvisioning(true, false, kWiFiLossGraceMs));
}

void setup() {
  UNITY_BEGIN();
  RUN_TEST(test_sequential_chunks_assemble_and_complete);
  RUN_TEST(test_out_of_order_chunks_assemble_and_complete);
  RUN_TEST(test_a_gap_is_not_complete);
  RUN_TEST(test_overlap_is_refused_rather_than_overwritten);
  RUN_TEST(test_a_chunk_past_capacity_is_refused);
  RUN_TEST(test_an_empty_chunk_is_refused);
  RUN_TEST(test_reset_clears_both_the_bytes_and_the_coverage);
  RUN_TEST(test_valid_credentials_pass);
  RUN_TEST(test_an_open_network_is_allowed);
  RUN_TEST(test_each_bad_field_is_named);
  RUN_TEST(test_the_setup_code_is_always_six_digits);
  RUN_TEST(test_no_credentials_before_the_setup_code);
  RUN_TEST(test_three_wrong_codes_lock_the_connection_out);
  RUN_TEST(test_a_correct_code_opens_the_window);
  RUN_TEST(test_the_window_closes_after_sixty_seconds);
  RUN_TEST(test_a_second_phone_is_refused_while_one_is_connected);
  RUN_TEST(test_a_disconnect_returns_to_advertising);
  RUN_TEST(test_an_idle_connection_is_dropped);
  RUN_TEST(test_the_happy_path_reaches_running);
  RUN_TEST(test_steps_out_of_order_are_refused);
  RUN_TEST(test_a_failure_carries_a_reason);
  RUN_TEST(test_an_unconfigured_gateway_advertises_immediately);
  RUN_TEST(test_a_running_gateway_never_advertises);
  RUN_TEST(test_a_short_wifi_blip_does_not_open_provisioning);
  UNITY_END();
}

void loop() {}
