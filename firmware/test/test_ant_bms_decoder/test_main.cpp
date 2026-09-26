#include <Arduino.h>
#include <unity.h>

#include "bms/AntBmsDecoder.h"

using namespace jkbmsr;

// Synthetic ANT "2021 BMS" status response, hand-built to match the documented
// frame layout: 4 cells (3.300/3.310/3.290/3.305V), 2 NTC temp sensors
// (25C/26C), MOSFET temp 35C, balancer temp 33C, 52.00V, +12.5A (charging),
// 82% SOC, 98% SOH, charge+discharge MOS on, balancer running (bitmask 7 at
// frame 26..33), warning bit set (errors = 1<<16). Not a real device capture —
// see devices/ANT_BLE/fixtures/README.md. CRC-16/MODBUS and every decoded
// value were computed by an independent Python script before use.
static const uint8_t kAntStatusFrame[] = {
    0x7E, 0xA1, 0x11, 0x00, 0x00, 0x48, 0x00, 0x00, 0x02, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0xE4, 0x0C, 0xEE, 0x0C, 0xDA, 0x0C, 0xE9, 0x0C, 0x19, 0x00, 0x1A, 0x00, 0x23, 0x00,
    0x21, 0x00, 0x50, 0x14, 0x7D, 0x00, 0x52, 0x00, 0x62, 0x00, 0x01, 0x01, 0x04, 0x00, 0x00, 0xC2,
    0xEB, 0x0B, 0x00, 0x95, 0xBA, 0x0A, 0xBC, 0x02, 0x00, 0x00, 0x8A, 0x02, 0x00, 0x00, 0x99, 0x99,
    0xAA, 0x55,
};

void test_parse_status_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(
      AntBmsDecoder::parseStatusFrame(kAntStatusFrame, sizeof(kAntStatusFrame), t));
  TEST_ASSERT_EQUAL_UINT8(4, t.cellCount);
  TEST_ASSERT_EQUAL_UINT8(2, t.temperatureSensorCount);
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
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 25.0f, t.temperature1);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 26.0f, t.temperature2);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 35.0f, t.mosfetTemperature);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 52.0f, t.packVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 12.5f, t.packCurrent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 650.0f, t.power);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 82.0f, t.stateOfCharge);
  TEST_ASSERT_EQUAL_UINT8(98, t.stateOfHealth);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 200.0f, t.fullCapacityAh);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 180.0f, t.remainingCapacityAh);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.7f, t.cycleCapacityAh);
  TEST_ASSERT_TRUE(t.chargingEnabled);
  TEST_ASSERT_TRUE(t.dischargingEnabled);
  TEST_ASSERT_TRUE(t.balancingActive);
  TEST_ASSERT_EQUAL_UINT32(0x00010000, t.errorsBitmask);
  TEST_ASSERT_EQUAL_STRING("ble", t.source);
  TEST_ASSERT_TRUE(t.valid);
}

void test_build_status_request_frame() {
  uint8_t frame[AntBmsDecoder::kRequestFrameSize];
  AntBmsDecoder::buildStatusRequest(frame);
  TEST_ASSERT_EQUAL_HEX8(0x7E, frame[0]);
  TEST_ASSERT_EQUAL_HEX8(0xA1, frame[1]);
  TEST_ASSERT_EQUAL_HEX8(0x01, frame[2]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[3]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[4]);
  TEST_ASSERT_EQUAL_HEX8(0xBE, frame[5]);
  const uint16_t crc = AntBmsDecoder::crc16Modbus(frame + 1, 5);
  TEST_ASSERT_EQUAL_HEX8(crc & 0xFF, frame[6]);
  TEST_ASSERT_EQUAL_HEX8((crc >> 8) & 0xFF, frame[7]);
  TEST_ASSERT_EQUAL_HEX8(0xAA, frame[8]);
  TEST_ASSERT_EQUAL_HEX8(0x55, frame[9]);
}

void test_rejects_bad_crc() {
  uint8_t frame[sizeof(kAntStatusFrame)];
  memcpy(frame, kAntStatusFrame, sizeof(frame));
  frame[sizeof(frame) - 6] ^= 0xFF;
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(AntBmsDecoder::parseStatusFrame(frame, sizeof(frame), t));
}

void test_rejects_wrong_length() {
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(
      AntBmsDecoder::parseStatusFrame(kAntStatusFrame, sizeof(kAntStatusFrame) - 1, t));
}

void test_rejects_wrong_function() {
  uint8_t frame[sizeof(kAntStatusFrame)];
  memcpy(frame, kAntStatusFrame, sizeof(frame));
  frame[2] = 0x21;
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(AntBmsDecoder::parseStatusFrame(frame, sizeof(frame), t));
}

void test_rejects_missing_end_marker() {
  uint8_t frame[sizeof(kAntStatusFrame)];
  memcpy(frame, kAntStatusFrame, sizeof(frame));
  frame[sizeof(frame) - 1] = 0x00;
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(AntBmsDecoder::parseStatusFrame(frame, sizeof(frame), t));
}

void test_crc16_modbus_known_vector() {
  // CRC-16/MODBUS("123456789") == 0x4B37.
  const uint8_t data[] = {'1', '2', '3', '4', '5', '6', '7', '8', '9'};
  TEST_ASSERT_EQUAL_HEX16(0x4B37, AntBmsDecoder::crc16Modbus(data, sizeof(data)));
}

void setup() {
  delay(2000);
  UNITY_BEGIN();
  RUN_TEST(test_parse_status_frame);
  RUN_TEST(test_build_status_request_frame);
  RUN_TEST(test_rejects_bad_crc);
  RUN_TEST(test_rejects_wrong_length);
  RUN_TEST(test_rejects_wrong_function);
  RUN_TEST(test_rejects_missing_end_marker);
  RUN_TEST(test_crc16_modbus_known_vector);
  UNITY_END();
}

void loop() {}