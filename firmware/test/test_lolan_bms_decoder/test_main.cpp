#include <Arduino.h>
#include <unity.h>

#include "bms/LolanBmsDecoder.h"

using namespace jkbmsr;

// Synthetic Lolan frames, hand-built to match the documented layout
// ([frameType] 0x00 [payload...], status/cell-info = 40 bytes, float32
// big-endian, no checksum on these two frame types). Not real device
// captures — see devices/LOLAN_BLE/fixtures/README.md.
//
// Status (0x01): 52.00V, +12.5A charging, 650.0W, temps 25C/26C, 42 cycles,
// 82% SOC, charging on / discharging off, error 1. CellInfo (0x02) carries 4
// cells 3.300/3.310/3.290/3.305V with balancing active on cells 1-2. Every
// decoded value was computed by an independent Python script before use.
static const uint8_t kLolanStatusFrame[] = {
    0x01, 0x00, 0x04, 0x01, 0x42, 0x50, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x41, 0x48, 0x00, 0x00,
    0x41, 0xC8, 0x00, 0x00, 0x41, 0xD0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x2A, 0x00, 0x52,
};

static const uint8_t kLolanCellInfoFrame[] = {
    0x02, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x53, 0x33, 0x33, 0x40, 0x53, 0xD7, 0x0A,
    0x40, 0x52, 0x8F, 0x5C, 0x40, 0x53, 0x85, 0x1F,
};

void test_parse_status_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(
      LolanBmsDecoder::parseStatusFrame(kLolanStatusFrame, sizeof(kLolanStatusFrame), t));
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 52.0f, t.packVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 12.5f, t.packCurrent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 650.0f, t.power);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 82.0f, t.stateOfCharge);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 25.0f, t.temperature1);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 26.0f, t.temperature2);
  TEST_ASSERT_EQUAL_UINT32(42, t.cycleCount);
  TEST_ASSERT_TRUE(t.chargingEnabled);
  TEST_ASSERT_FALSE(t.dischargingEnabled);
  TEST_ASSERT_EQUAL_UINT32(1, t.errorsBitmask);
  TEST_ASSERT_EQUAL_STRING("ble", t.source);
  TEST_ASSERT_TRUE(t.valid);
}

void test_parse_cell_info_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(
      LolanBmsDecoder::parseCellInfoFrame(kLolanCellInfoFrame, sizeof(kLolanCellInfoFrame), t));
  TEST_ASSERT_EQUAL_UINT8(4, t.cellCount);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.300f, t.cellVoltages[0]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.310f, t.cellVoltages[1]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.290f, t.cellVoltages[2]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.305f, t.cellVoltages[3]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.310f, t.maxCellVoltage);
  TEST_ASSERT_EQUAL_UINT8(2, t.maxVoltageCell);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.290f, t.minCellVoltage);
  TEST_ASSERT_EQUAL_UINT8(3, t.minVoltageCell);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 0.020f, t.deltaCellVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.30125f, t.avgCellVoltage);
  TEST_ASSERT_TRUE(t.balancingActive);
  TEST_ASSERT_TRUE(t.valid);
}

void test_build_command_frame() {
  uint8_t frame[LolanBmsDecoder::kRequestFrameSize];
  LolanBmsDecoder::buildCommandFrame(frame, LolanBmsDecoder::kCommandStatus,
                                     LolanBmsDecoder::kDefaultPassword);
  TEST_ASSERT_EQUAL_HEX8(0xC5, frame[0]);
  TEST_ASSERT_EQUAL_HEX8(0x65, frame[1]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[2]);
  TEST_ASSERT_EQUAL_HEX8(0xBC, frame[3]);
  TEST_ASSERT_EQUAL_HEX8(0x61, frame[4]);
  TEST_ASSERT_EQUAL_HEX8(0x4E, frame[5]);
}

void test_response_size_for() {
  TEST_ASSERT_EQUAL_UINT(40, LolanBmsDecoder::responseSizeFor(kLolanStatusFrame, 4));
  TEST_ASSERT_EQUAL_UINT(40, LolanBmsDecoder::responseSizeFor(kLolanCellInfoFrame, 4));
  TEST_ASSERT_EQUAL_UINT(108, LolanBmsDecoder::responseSizeFor(
                                  (const uint8_t*) "\x03", 1));
  TEST_ASSERT_EQUAL_UINT(0, LolanBmsDecoder::responseSizeFor((const uint8_t*) "\x7E", 1));
}

void test_be_float32() {
  const uint8_t bytes[] = {0x41, 0x48, 0x00, 0x00};
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 12.5f, LolanBmsDecoder::beFloat32(bytes));
}

void test_rejects_truncated_frames() {
  BatteryTelemetry t;
  // A 39-byte prefix is incomplete for a status frame.
  TEST_ASSERT_FALSE(
      LolanBmsDecoder::parseStatusFrame(kLolanStatusFrame, sizeof(kLolanStatusFrame) - 1, t));
  TEST_ASSERT_FALSE(
      LolanBmsDecoder::parseCellInfoFrame(kLolanCellInfoFrame, sizeof(kLolanCellInfoFrame) - 1, t));
}

void setup() {
  delay(2000);
  UNITY_BEGIN();
  RUN_TEST(test_parse_status_frame);
  RUN_TEST(test_parse_cell_info_frame);
  RUN_TEST(test_build_command_frame);
  RUN_TEST(test_response_size_for);
  RUN_TEST(test_be_float32);
  RUN_TEST(test_rejects_truncated_frames);
  UNITY_END();
}

void loop() {}