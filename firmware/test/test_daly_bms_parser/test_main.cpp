#include <Arduino.h>
#include <unity.h>

#include "bms/DalyBmsParser.h"

using namespace jkbmsr;

// Synthetic 0x90 (voltage/current/SOC) response, hand-built to match the
// documented 13-byte frame layout: 52.0V, +12.5A (charging), 82.0% SOC.
// Not a real device capture — see devices/DALY_UART_0xA5/fixtures/README.md.
static const uint8_t kPackMeasurementsFrame[] = {
    0xA5, 0x01, 0x90, 0x08, 0x02, 0x08, 0x00, 0x00, 0x75, 0xAD, 0x03, 0x34, 0xA1,
};

// Synthetic 0x91 (min/max cell voltage) response: max 3.350V on cell 5,
// min 3.280V on cell 12.
static const uint8_t kMinMaxCellVoltageFrame[] = {
    0xA5, 0x01, 0x91, 0x08, 0x0D, 0x16, 0x05, 0x0C, 0xD0, 0x0C, 0x00, 0x00, 0x4F,
};

void test_parse_pack_measurements_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(
      DalyBmsParser::parseFrame(kPackMeasurementsFrame, sizeof(kPackMeasurementsFrame), 0x90, t));
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 52.0f, t.packVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 12.5f, t.packCurrent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 82.0f, t.stateOfCharge);
  TEST_ASSERT_FLOAT_WITHIN(0.5f, 650.0f, t.power);
}

void test_parse_min_max_cell_voltage_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(
      DalyBmsParser::parseFrame(kMinMaxCellVoltageFrame, sizeof(kMinMaxCellVoltageFrame), 0x91, t));
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 3.350f, t.maxCellVoltage);
  TEST_ASSERT_EQUAL_UINT8(5, t.maxVoltageCell);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 3.280f, t.minCellVoltage);
  TEST_ASSERT_EQUAL_UINT8(12, t.minVoltageCell);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 0.070f, t.deltaCellVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 3.315f, t.avgCellVoltage);
}

void test_rejects_bad_checksum() {
  uint8_t frame[sizeof(kPackMeasurementsFrame)];
  memcpy(frame, kPackMeasurementsFrame, sizeof(frame));
  frame[sizeof(frame) - 1] ^= 0xFF;
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(DalyBmsParser::parseFrame(frame, sizeof(frame), 0x90, t));
}

void test_rejects_command_mismatch() {
  BatteryTelemetry t;
  // Frame is a genuine 0x90 response; asking parseFrame to treat it as a
  // 0x91 response must fail rather than silently misinterpret the bytes.
  TEST_ASSERT_FALSE(
      DalyBmsParser::parseFrame(kPackMeasurementsFrame, sizeof(kPackMeasurementsFrame), 0x91, t));
}

void test_rejects_wrong_length() {
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(
      DalyBmsParser::parseFrame(kPackMeasurementsFrame, sizeof(kPackMeasurementsFrame) - 1, 0x90, t));
}

void test_rejects_frames_without_header() {
  uint8_t frame[sizeof(kPackMeasurementsFrame)];
  memcpy(frame, kPackMeasurementsFrame, sizeof(frame));
  frame[0] = 0x00;
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(DalyBmsParser::parseFrame(frame, sizeof(frame), 0x90, t));
}

void setup() {
  delay(2000);
  UNITY_BEGIN();
  RUN_TEST(test_parse_pack_measurements_frame);
  RUN_TEST(test_parse_min_max_cell_voltage_frame);
  RUN_TEST(test_rejects_bad_checksum);
  RUN_TEST(test_rejects_command_mismatch);
  RUN_TEST(test_rejects_wrong_length);
  RUN_TEST(test_rejects_frames_without_header);
  UNITY_END();
}

void loop() {}
