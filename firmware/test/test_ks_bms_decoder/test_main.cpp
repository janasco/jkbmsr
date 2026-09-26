#include <Arduino.h>
#include <unity.h>

#include "bms/KsBmsDecoder.h"

using namespace jkbmsr;

// Synthetic KS48100 frames, hand-built to match the documented layout
// (7B <type> <len> <payload> 7D, no checksum, big-endian values). Not real
// device captures — see devices/KS48100_BLE/fixtures/README.md.
//
// Status (0x01): 82% SOC, 52.00V, +12.5A, 650.0W, temps 25/26C (NTCs) and
// 35C MOSFET, 180.00Ah remaining / 200.00Ah full, 0.70Ah cycle capacity, 42
// cycles, balancing active (mask 7), charge+discharge FETs on, error 1, 98%
// SOH. The cell frame (0x02) carries 4 cells 3.300..3.305V. Every decoded
// value was computed by an independent Python script before use.
static const uint8_t kKsStatusFrame[] = {
    0x7B, 0x01, 0x20, 0x00, 0x52, 0x14, 0x50, 0x00, 0xFA, 0x01, 0x04, 0x01, 0x5E, 0x04, 0xE2, 0x46,
    0x50, 0x4E, 0x20, 0x00, 0x00, 0x00, 0x46, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x07, 0x00, 0x0C, 0x00,
    0x01, 0x00, 0x62, 0x7D,
};

static const uint8_t kKsCellFrame[] = {
    0x7B, 0x02, 0x09, 0x04, 0x0C, 0xE4, 0x0C, 0xEE, 0x0C, 0xDA, 0x0C, 0xE9, 0x7D,
};

void test_parse_status_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(KsBmsDecoder::parseStatusFrame(kKsStatusFrame, sizeof(kKsStatusFrame), t));
  TEST_ASSERT_EQUAL_UINT8(2, t.temperatureSensorCount);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 82.0f, t.stateOfCharge);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 52.0f, t.packVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 12.5f, t.packCurrent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 650.0f, t.power);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 25.0f, t.temperature1);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 26.0f, t.temperature2);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 35.0f, t.mosfetTemperature);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 180.0f, t.remainingCapacityAh);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 200.0f, t.fullCapacityAh);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.70f, t.cycleCapacityAh);
  TEST_ASSERT_EQUAL_UINT32(42, t.cycleCount);
  TEST_ASSERT_TRUE(t.balancingActive);
  TEST_ASSERT_TRUE(t.chargingEnabled);
  TEST_ASSERT_TRUE(t.dischargingEnabled);
  TEST_ASSERT_EQUAL_UINT32(1, t.errorsBitmask);
  TEST_ASSERT_EQUAL_UINT8(98, t.stateOfHealth);
  TEST_ASSERT_EQUAL_STRING("ble", t.source);
  TEST_ASSERT_TRUE(t.valid);
}

void test_parse_status_type2() {
  uint8_t frame[sizeof(kKsStatusFrame)];
  memcpy(frame, kKsStatusFrame, sizeof(frame));
  frame[1] = 0x61;  // device type 2 variant, layout-identical
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(KsBmsDecoder::parseStatusFrame(frame, sizeof(frame), t));
  TEST_ASSERT_EQUAL_UINT8(98, t.stateOfHealth);
}

void test_parse_cell_voltages() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(KsBmsDecoder::parseCellVoltagesFrame(kKsCellFrame, sizeof(kKsCellFrame), t));
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
  TEST_ASSERT_TRUE(t.valid);
}

void test_build_command_frame() {
  uint8_t frame[KsBmsDecoder::kRequestFrameSize];
  KsBmsDecoder::buildCommandFrame(frame, KsBmsDecoder::kFrameTypeStatus);
  TEST_ASSERT_EQUAL_HEX8(0x7B, frame[0]);
  TEST_ASSERT_EQUAL_HEX8(0x01, frame[1]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[2]);
  TEST_ASSERT_EQUAL_HEX8(0x7D, frame[3]);
}

void test_is_complete_frame() {
  TEST_ASSERT_TRUE(KsBmsDecoder::isCompleteFrame(kKsCellFrame, sizeof(kKsCellFrame)));
  TEST_ASSERT_FALSE(KsBmsDecoder::isCompleteFrame(kKsCellFrame, sizeof(kKsCellFrame) - 1));
  uint8_t frame[sizeof(kKsCellFrame)];
  memcpy(frame, kKsCellFrame, sizeof(frame));
  frame[sizeof(frame) - 1] = 0x00;
  TEST_ASSERT_FALSE(KsBmsDecoder::isCompleteFrame(frame, sizeof(frame)));
}

void test_status_without_soh_is_accepted() {
  // A short status frame (len 31, 35 bytes total) still parses; SOH stays
  // 0xFF (not available).
  uint8_t frame[sizeof(kKsStatusFrame)];
  memcpy(frame, kKsStatusFrame, sizeof(frame));
  const size_t shortLen = 35;
  frame[2] = static_cast<uint8_t>(shortLen - 4);
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(KsBmsDecoder::parseStatusFrame(frame, shortLen, t));
  TEST_ASSERT_EQUAL_HEX8(0xFF, t.stateOfHealth);
}

void setup() {
  delay(2000);
  UNITY_BEGIN();
  RUN_TEST(test_parse_status_frame);
  RUN_TEST(test_parse_status_type2);
  RUN_TEST(test_parse_cell_voltages);
  RUN_TEST(test_build_command_frame);
  RUN_TEST(test_is_complete_frame);
  RUN_TEST(test_status_without_soh_is_accepted);
  UNITY_END();
}

void loop() {}