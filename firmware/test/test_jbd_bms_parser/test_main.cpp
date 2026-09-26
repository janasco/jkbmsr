#include <Arduino.h>
#include <unity.h>

#include "bms/JbdBmsParser.h"

using namespace jkbmsr;

// Synthetic 0x03 (hardware info) response, hand-built to match the frame
// layout documented in syssi/esphome-jbd-bms: 52.00V, +10.00A (charging),
// 180/200 Ah, 42 cycles, cell 1 balancing, no errors, 88% SOC, charging
// only, 16 cells, 2 temperature sensors (25.0C / 26.0C). Not a real device
// capture — see devices/JBD_UART/fixtures/README.md.
static const uint8_t kHardwareInfoFrame[] = {
    0xDD, 0x03, 0x00, 0x1B,
    0x14, 0x50,              // total voltage: 5200 -> 52.00V
    0x03, 0xE8,              // current: +1000 -> +10.00A
    0x46, 0x50,              // residual capacity: 18000 -> 180.00Ah
    0x4E, 0x20,              // nominal capacity: 20000 -> 200.00Ah
    0x00, 0x2A,              // cycle count: 42
    0x00, 0x00,              // production date (unused)
    0x00, 0x00, 0x00, 0x01,  // balance status bitmask: cell 1 balancing
    0x00, 0x00,              // protection/errors bitmask: none
    0x10,                    // software version
    0x58,                    // SOC: 88%
    0x01,                    // operation status: charging only
    0x10,                    // cell count: 16
    0x02,                    // temperature sensor count: 2
    0x0B, 0xA5,               // temperature 1: 2981 -> 25.0C
    0x0B, 0xAF,               // temperature 2: 2991 -> 26.0C
    0xFB, 0x82,               // checksum
    0x77,
};

// Synthetic 0x04 (cell info) response: 4 cells at 3.300V / 3.310V / 3.290V / 3.305V.
static const uint8_t kCellInfoFrame[] = {
    0xDD, 0x04, 0x00, 0x08,
    0x0C, 0xE4,  // cell 1: 3300 -> 3.300V
    0x0C, 0xEE,  // cell 2: 3310 -> 3.310V
    0x0C, 0xDA,  // cell 3: 3290 -> 3.290V
    0x0C, 0xE9,  // cell 4: 3305 -> 3.305V
    0xFC, 0x33,  // checksum
    0x77,
};

void test_parse_hardware_info_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(JbdBmsParser::parseFrame(kHardwareInfoFrame, sizeof(kHardwareInfoFrame), t));
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 52.00f, t.packVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 10.00f, t.packCurrent);
  TEST_ASSERT_FLOAT_WITHIN(0.5f, 520.0f, t.power);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 180.00f, t.remainingCapacityAh);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 200.00f, t.fullCapacityAh);
  TEST_ASSERT_EQUAL_UINT32(42, t.cycleCount);
  TEST_ASSERT_TRUE(t.balancingActive);
  TEST_ASSERT_EQUAL_UINT32(0, t.errorsBitmask);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 88.0f, t.stateOfCharge);
  TEST_ASSERT_TRUE(t.chargingEnabled);
  TEST_ASSERT_FALSE(t.dischargingEnabled);
  TEST_ASSERT_EQUAL_UINT8(16, t.cellCount);
  TEST_ASSERT_EQUAL_UINT8(2, t.temperatureSensorCount);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 25.0f, t.temperature1);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 26.0f, t.temperature2);
}

void test_parse_cell_info_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(JbdBmsParser::parseFrame(kCellInfoFrame, sizeof(kCellInfoFrame), t));
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
}

void test_rejects_bad_checksum() {
  uint8_t frame[sizeof(kHardwareInfoFrame)];
  memcpy(frame, kHardwareInfoFrame, sizeof(frame));
  frame[sizeof(frame) - 2] ^= 0xFF;
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(JbdBmsParser::parseFrame(frame, sizeof(frame), t));
}

void test_rejects_truncated_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(
      JbdBmsParser::parseFrame(kHardwareInfoFrame, sizeof(kHardwareInfoFrame) - 10, t));
}

void test_rejects_frames_without_header() {
  const uint8_t frame[] = {0x00, 0x03, 0x00, 0x00, 0xFF, 0xFD, 0x77};
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(JbdBmsParser::parseFrame(frame, sizeof(frame), t));
}

void test_rejects_frames_without_trailer() {
  uint8_t frame[sizeof(kHardwareInfoFrame)];
  memcpy(frame, kHardwareInfoFrame, sizeof(frame));
  frame[sizeof(frame) - 1] = 0x00;
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(JbdBmsParser::parseFrame(frame, sizeof(frame), t));
}

void setup() {
  delay(2000);
  UNITY_BEGIN();
  RUN_TEST(test_parse_hardware_info_frame);
  RUN_TEST(test_parse_cell_info_frame);
  RUN_TEST(test_rejects_bad_checksum);
  RUN_TEST(test_rejects_truncated_frame);
  RUN_TEST(test_rejects_frames_without_header);
  RUN_TEST(test_rejects_frames_without_trailer);
  UNITY_END();
}

void loop() {}
