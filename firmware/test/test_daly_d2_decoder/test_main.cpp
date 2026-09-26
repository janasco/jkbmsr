#include <Arduino.h>
#include <unity.h>

#include "bms/DalyD2Decoder.h"

using namespace jkbmsr;

// Synthetic 62-register (129-byte) status response, hand-built to match the
// documented frame layout: 4 cells (3.300/3.310/3.290/3.305V), 2 temp
// sensors (25C/26C), 52.00V, +12.5A (charging), 82.0% SOC, 180.0Ah
// remaining, 42 cycles, balancing + charging (not discharging), error
// bitmask 0x5. Not a real device capture — see
// devices/DALY_BLE_D2/fixtures/README.md.
static const uint8_t kStatusFrame62[] = {
    0xD2, 0x03, 0x7C, 0x0C, 0xE4, 0x0C, 0xEE, 0x0C, 0xDA, 0x0C, 0xE9, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x41, 0x00, 0x42, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x02, 0x08, 0x75, 0xAD, 0x03, 0x34, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x07, 0x08, 0x00, 0x04, 0x00, 0x02, 0x00, 0x2A, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0xA1, 0xA3,
};

// Synthetic 80-register (165-byte) status response — same core values as
// above, plus the bonus fields only this larger size carries: balancing
// current +0.8A, MOSFET temperature 35C, board temperature 28C (not
// decoded — no BatteryTelemetry field for it).
static const uint8_t kStatusFrame80[] = {
    0xD2, 0x03, 0xA0, 0x0C, 0xE4, 0x0C, 0xEE, 0x0C, 0xDA, 0x0C, 0xE9, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x41, 0x00, 0x42, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x02, 0x08, 0x75, 0xAD, 0x03, 0x34, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x07, 0x08, 0x00, 0x04, 0x00, 0x02, 0x00, 0x2A, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00,
    0x00, 0x78, 0x50, 0x00, 0x00, 0x00, 0x4B, 0x00, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xE1,
    0x18,
};

void test_parse_62_register_status_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(DalyD2Decoder::parseStatusFrame(kStatusFrame62, sizeof(kStatusFrame62), t));
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
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 52.00f, t.packVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 12.5f, t.packCurrent);
  TEST_ASSERT_FLOAT_WITHIN(0.5f, 650.0f, t.power);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 82.0f, t.stateOfCharge);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 180.0f, t.remainingCapacityAh);
  TEST_ASSERT_EQUAL_UINT32(42, t.cycleCount);
  TEST_ASSERT_TRUE(t.balancingActive);
  TEST_ASSERT_TRUE(t.chargingEnabled);
  TEST_ASSERT_FALSE(t.dischargingEnabled);
  TEST_ASSERT_EQUAL_UINT32(5, t.errorsBitmask);
  TEST_ASSERT_EQUAL_STRING("ble", t.source);
  // Bonus fields are 80-register-only; the smaller response mustn't touch them.
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 0.0f, t.balancingCurrent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.0f, t.mosfetTemperature);
}

void test_parse_80_register_status_frame_bonus_fields() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(DalyD2Decoder::parseStatusFrame(kStatusFrame80, sizeof(kStatusFrame80), t));
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 52.00f, t.packVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 0.8f, t.balancingCurrent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 35.0f, t.mosfetTemperature);
}

void test_rejects_bad_checksum() {
  uint8_t frame[sizeof(kStatusFrame62)];
  memcpy(frame, kStatusFrame62, sizeof(frame));
  frame[sizeof(frame) - 1] ^= 0xFF;
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(DalyD2Decoder::parseStatusFrame(frame, sizeof(frame), t));
}

void test_rejects_wrong_length() {
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(DalyD2Decoder::parseStatusFrame(kStatusFrame62, sizeof(kStatusFrame62) - 1, t));
}

void test_rejects_frames_without_header() {
  uint8_t frame[sizeof(kStatusFrame62)];
  memcpy(frame, kStatusFrame62, sizeof(frame));
  frame[0] = 0x00;
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(DalyD2Decoder::parseStatusFrame(frame, sizeof(frame), t));
}

void test_build_status_request_frame() {
  uint8_t frame[8];
  DalyD2Decoder::buildStatusRequest(frame);
  TEST_ASSERT_EQUAL_HEX8(0xD2, frame[0]);
  TEST_ASSERT_EQUAL_HEX8(0x03, frame[1]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[2]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[3]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[4]);
  TEST_ASSERT_EQUAL_HEX8(62, frame[5]);
  const uint16_t crc = DalyD2Decoder::crc16Modbus(frame, 6);
  TEST_ASSERT_EQUAL_HEX8(static_cast<uint8_t>(crc), frame[6]);
  TEST_ASSERT_EQUAL_HEX8(static_cast<uint8_t>(crc >> 8), frame[7]);
}

void setup() {
  delay(2000);
  UNITY_BEGIN();
  RUN_TEST(test_parse_62_register_status_frame);
  RUN_TEST(test_parse_80_register_status_frame_bonus_fields);
  RUN_TEST(test_rejects_bad_checksum);
  RUN_TEST(test_rejects_wrong_length);
  RUN_TEST(test_rejects_frames_without_header);
  RUN_TEST(test_build_status_request_frame);
  UNITY_END();
}

void loop() {}
