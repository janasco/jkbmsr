#include <Arduino.h>
#include <unity.h>

#include "bms/SeplosBleDecoder.h"

using namespace jkbmsr;

// Synthetic "single machine data" (0x61) response, hand-built to match the
// documented frame layout: 4 cells (3.300/3.310/3.290/3.305V), 4 temp
// sensors (2 cell probes at 25C/26C, ambient 22C, MOSFET 35C), 52.00V,
// +12.5A (charging), 82.0% SOC, 180.00Ah remaining, 200.00Ah nominal, 42
// cycles, 98.5% SOH, charging switch on / discharging switch off, alarm
// bytes 1-2 set (0x01, 0x02). Not a real device capture — see
// devices/SEPLOS_BLE/fixtures/README.md. CRC-16/XMODEM and every decoded
// value independently cross-checked with a throwaway Python script before
// use.
static const uint8_t kSingleMachineDataFrame[] = {
    0x7E, 0x10, 0x00, 0x46, 0x61, 0x00, 0x51, 0x00, 0x00, 0x04, 0x0C, 0xE4, 0x0C, 0xEE, 0x0C, 0xDA,
    0x0C, 0xE9, 0x04, 0x0B, 0xA5, 0x0B, 0xAF, 0x0B, 0x87, 0x0C, 0x09, 0x04, 0xE2, 0x14, 0x50, 0x46,
    0x50, 0x00, 0x4E, 0x20, 0x03, 0x34, 0x4E, 0x20, 0x00, 0x2A, 0x03, 0xD9, 0x14, 0x50, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x02, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xE3, 0x62, 0x0D,
};

// The frame is exactly 91 bytes: a 7-byte header, an 81-byte declared payload,
// 2 CRC bytes and the 0x0D trailer. It previously carried two bytes too few,
// so parseSingleMachineDataFrame rejected it at `length != frameLen` — and
// because no firmware test has ever actually executed, the test asserting a
// successful parse was never able to fail. Every decoded value below was
// re-derived against the decoder with a host build.
static const size_t kSingleMachineDataFrameLen = sizeof(kSingleMachineDataFrame);

// XMODEM CRC-16 over frame[1 .. frameLen-4], matching the decoder's own
// coverage window. Lets a regression test mutate a header byte and re-seal
// the frame so it reaches the field under test instead of being turned away
// by the CRC check first.
static void resealFrame(uint8_t* frame, size_t frameLen) {
  uint16_t crc = 0x0000;
  for (size_t i = 1; i <= frameLen - 4; ++i) {
    crc ^= static_cast<uint16_t>(frame[i]) << 8;
    for (int bit = 0; bit < 8; ++bit) {
      crc = (crc & 0x8000) ? static_cast<uint16_t>((crc << 1) ^ 0x1021)
                           : static_cast<uint16_t>(crc << 1);
    }
  }
  frame[frameLen - 3] = static_cast<uint8_t>(crc >> 8);
  frame[frameLen - 2] = static_cast<uint8_t>(crc & 0xFF);
}

void test_parse_single_machine_data_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(SeplosBleDecoder::parseSingleMachineDataFrame(kSingleMachineDataFrame,
                                                                  sizeof(kSingleMachineDataFrame), t));
  TEST_ASSERT_EQUAL_UINT8(4, t.cellCount);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 3.300f, t.cellVoltages[0]);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 3.310f, t.cellVoltages[1]);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 3.290f, t.cellVoltages[2]);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 3.305f, t.cellVoltages[3]);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 3.310f, t.maxCellVoltage);
  TEST_ASSERT_EQUAL_UINT8(2, t.maxVoltageCell);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 3.290f, t.minCellVoltage);
  TEST_ASSERT_EQUAL_UINT8(3, t.minVoltageCell);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 0.020f, t.deltaCellVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 3.30125f, t.avgCellVoltage);
  TEST_ASSERT_EQUAL_UINT8(2, t.temperatureSensorCount);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 25.0f, t.temperature1);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 26.0f, t.temperature2);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 35.0f, t.mosfetTemperature);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 12.5f, t.packCurrent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 52.0f, t.packVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.5f, 650.0f, t.power);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 180.0f, t.remainingCapacityAh);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 82.0f, t.stateOfCharge);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 200.0f, t.fullCapacityAh);
  TEST_ASSERT_EQUAL_UINT32(42, t.cycleCount);
  // 98.5% rounded half-up to the nearest integer percent (stateOfHealth is uint8_t).
  TEST_ASSERT_EQUAL_UINT8(99, t.stateOfHealth);
  TEST_ASSERT_TRUE(t.chargingEnabled);
  TEST_ASSERT_FALSE(t.dischargingEnabled);
  TEST_ASSERT_EQUAL_UINT32(0x0201, t.errorsBitmask);
  TEST_ASSERT_EQUAL_STRING("ble", t.source);
  TEST_ASSERT_TRUE(t.valid);
}

void test_rejects_bad_checksum() {
  uint8_t frame[sizeof(kSingleMachineDataFrame)];
  memcpy(frame, kSingleMachineDataFrame, sizeof(frame));
  frame[sizeof(frame) - 2] ^= 0xFF;
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(SeplosBleDecoder::parseSingleMachineDataFrame(frame, sizeof(frame), t));
}

void test_rejects_wrong_length() {
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(
      SeplosBleDecoder::parseSingleMachineDataFrame(kSingleMachineDataFrame, sizeof(kSingleMachineDataFrame) - 1, t));
}

void test_rejects_frames_without_header() {
  uint8_t frame[sizeof(kSingleMachineDataFrame)];
  memcpy(frame, kSingleMachineDataFrame, sizeof(frame));
  frame[0] = 0x00;
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(SeplosBleDecoder::parseSingleMachineDataFrame(frame, sizeof(frame), t));
}

void test_rejects_wrong_command_byte() {
  uint8_t frame[sizeof(kSingleMachineDataFrame)];
  memcpy(frame, kSingleMachineDataFrame, sizeof(frame));
  frame[3] = 0x51;  // SEPLOS_CMD_GET_MANUFACTURER_INFO, not implemented
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(SeplosBleDecoder::parseSingleMachineDataFrame(frame, sizeof(frame), t));
}

void test_build_single_machine_data_request_frame() {
  uint8_t frame[SeplosBleDecoder::kRequestFrameSize];
  SeplosBleDecoder::buildSingleMachineDataRequest(frame);
  TEST_ASSERT_EQUAL_HEX8(0x7E, frame[0]);
  TEST_ASSERT_EQUAL_HEX8(0x10, frame[1]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[2]);
  TEST_ASSERT_EQUAL_HEX8(0x46, frame[3]);
  TEST_ASSERT_EQUAL_HEX8(0x61, frame[4]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[5]);
  TEST_ASSERT_EQUAL_HEX8(0x01, frame[6]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[7]);
  TEST_ASSERT_EQUAL_HEX8(0xF7, frame[8]);
  TEST_ASSERT_EQUAL_HEX8(0xC1, frame[9]);
  TEST_ASSERT_EQUAL_HEX8(0x0D, frame[10]);
}

// Regression: `cells` (frame[9]) is radio-controlled and was used as an offset
// before being bounded. With cells=200 the temperature lookup reads offset
// 7+3+400 = 410, far past the frame and past the client's 256-byte assembly
// buffer — confirmed as a heap-buffer-overflow READ under ASan. The frame is
// rejected later regardless, so the assertion is on the rejection plus an
// untouched telemetry struct. The frame is re-sealed after the mutation so it
// reaches the cell read rather than being turned away by the CRC check.
void test_rejects_implausible_cell_count() {
  uint8_t frame[kSingleMachineDataFrameLen];
  memcpy(frame, kSingleMachineDataFrame, kSingleMachineDataFrameLen);
  frame[9] = 200;
  resealFrame(frame, kSingleMachineDataFrameLen);

  // The frame is otherwise valid: it must get past the CID/command check and
  // the CRC, which is exactly why the bound is needed at all.
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(
      SeplosBleDecoder::parseSingleMachineDataFrame(frame, kSingleMachineDataFrameLen, t));
  TEST_ASSERT_EQUAL_UINT8(0, t.cellCount);
}

// The command byte lives at frame[4]; frame[3] is the fixed CID 0x46. This
// previously compared frame[3] against 0x61, which rejected every real device
// — and the test claiming a successful parse never ran to catch it.
void test_accepts_command_byte_at_index_four() {
  TEST_ASSERT_EQUAL_HEX8(0x46, kSingleMachineDataFrame[3]);
  TEST_ASSERT_EQUAL_HEX8(0x61, kSingleMachineDataFrame[4]);

  // A frame carrying a different command must still be refused.
  uint8_t frame[kSingleMachineDataFrameLen];
  memcpy(frame, kSingleMachineDataFrame, kSingleMachineDataFrameLen);
  frame[4] = 0x62;
  resealFrame(frame, kSingleMachineDataFrameLen);
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(
      SeplosBleDecoder::parseSingleMachineDataFrame(frame, kSingleMachineDataFrameLen, t));
}

void setup() {
  delay(2000);
  UNITY_BEGIN();
  RUN_TEST(test_parse_single_machine_data_frame);
  RUN_TEST(test_rejects_bad_checksum);
  RUN_TEST(test_rejects_wrong_length);
  RUN_TEST(test_rejects_frames_without_header);
  RUN_TEST(test_rejects_wrong_command_byte);
  RUN_TEST(test_build_single_machine_data_request_frame);
  RUN_TEST(test_rejects_implausible_cell_count);
  RUN_TEST(test_accepts_command_byte_at_index_four);
  UNITY_END();
}

void loop() {}
