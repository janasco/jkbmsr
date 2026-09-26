#include <Arduino.h>
#include <unity.h>

#include "bms/TianpowerBmsDecoder.h"

using namespace jkbmsr;

// Synthetic Tianpower frames, hand-built to match the documented layout (fixed
// 20-byte envelopes 55 14 <type> ... AA, all multi-byte values big-endian, no
// checksum). Not real device captures — see
// devices/TIANPOWER_BLE/fixtures/README.md. The status frame carries 82% SOC,
// 52.00V, +12.5A, 25/26C NTC temps and a 35C MOSFET temp; the cell chunks put
// 3.300/3.310/3.290/3.305V in cells 1-4 (chunk 0x88) and 3.295/3.315/3.280/
// 3.300V in cells 9-12 (chunk 0x89). Every decoded value was computed by an
// independent Python script before use.
static const uint8_t kTianpowerStatusFrame[] = {
    0x55, 0x14, 0x83, 0x00, 0x52, 0x14, 0x50, 0x00, 0xFA, 0x01, 0x04, 0x01, 0x5E, 0x04, 0xE2, 0x00,
    0x00, 0x00, 0x00, 0xAA,
};

static const uint8_t kTianpowerCellChunk1_8[] = {
    0x55, 0x14, 0x88, 0x0C, 0xE4, 0x0C, 0xEE, 0x0C, 0xDA, 0x0C, 0xE9, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0xAA,
};

static const uint8_t kTianpowerCellChunk9_16[] = {
    0x55, 0x14, 0x89, 0x0C, 0xDF, 0x0C, 0xF3, 0x0C, 0xD0, 0x0C, 0xE4, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0xAA,
};

void test_parse_status_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(
      TianpowerBmsDecoder::parseStatusFrame(kTianpowerStatusFrame, sizeof(kTianpowerStatusFrame), t));
  TEST_ASSERT_EQUAL_UINT8(2, t.temperatureSensorCount);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 52.0f, t.packVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 12.5f, t.packCurrent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 650.0f, t.power);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 82.0f, t.stateOfCharge);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 25.0f, t.temperature1);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 26.0f, t.temperature2);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 35.0f, t.mosfetTemperature);
  TEST_ASSERT_EQUAL_STRING("ble", t.source);
  TEST_ASSERT_TRUE(t.valid);
}

void test_parse_cell_chunk() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(TianpowerBmsDecoder::parseCellChunkFrame(
      kTianpowerCellChunk1_8, sizeof(kTianpowerCellChunk1_8), t));
  TEST_ASSERT_EQUAL_UINT8(8, t.cellCount);
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

void test_parse_cell_chunk_high_range() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(TianpowerBmsDecoder::parseCellChunkFrame(
      kTianpowerCellChunk9_16, sizeof(kTianpowerCellChunk9_16), t));
  TEST_ASSERT_EQUAL_UINT8(16, t.cellCount);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.295f, t.cellVoltages[8]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.315f, t.cellVoltages[9]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.280f, t.cellVoltages[10]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.300f, t.cellVoltages[11]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.315f, t.maxCellVoltage);
  TEST_ASSERT_EQUAL_UINT8(10, t.maxVoltageCell);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.280f, t.minCellVoltage);
  TEST_ASSERT_EQUAL_UINT8(11, t.minVoltageCell);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 0.035f, t.deltaCellVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.2975f, t.avgCellVoltage);
}

void test_build_request_frame() {
  uint8_t frame[TianpowerBmsDecoder::kRequestFrameSize];
  TianpowerBmsDecoder::buildRequestFrame(frame, TianpowerBmsDecoder::kFrameTypeStatus);
  TEST_ASSERT_EQUAL_HEX8(0x55, frame[0]);
  TEST_ASSERT_EQUAL_HEX8(0x04, frame[1]);
  TEST_ASSERT_EQUAL_HEX8(0x83, frame[2]);
  TEST_ASSERT_EQUAL_HEX8(0xAA, frame[3]);
}

void test_is_complete_frame() {
  TEST_ASSERT_TRUE(TianpowerBmsDecoder::isCompleteFrame(
      kTianpowerStatusFrame, sizeof(kTianpowerStatusFrame)));
  TEST_ASSERT_FALSE(TianpowerBmsDecoder::isCompleteFrame(
      kTianpowerStatusFrame, sizeof(kTianpowerStatusFrame) - 1));
  uint8_t frame[sizeof(kTianpowerStatusFrame)];
  memcpy(frame, kTianpowerStatusFrame, sizeof(frame));
  frame[19] = 0x00;
  TEST_ASSERT_FALSE(TianpowerBmsDecoder::isCompleteFrame(frame, sizeof(frame)));
}

void test_rejects_wrong_type() {
  uint8_t frame[sizeof(kTianpowerStatusFrame)];
  memcpy(frame, kTianpowerStatusFrame, sizeof(frame));
  frame[2] = 0x87;  // temperatures frame, not decoded
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(TianpowerBmsDecoder::parseStatusFrame(frame, sizeof(frame), t));
}

void setup() {
  delay(2000);
  UNITY_BEGIN();
  RUN_TEST(test_parse_status_frame);
  RUN_TEST(test_parse_cell_chunk);
  RUN_TEST(test_parse_cell_chunk_high_range);
  RUN_TEST(test_build_request_frame);
  RUN_TEST(test_is_complete_frame);
  RUN_TEST(test_rejects_wrong_type);
  UNITY_END();
}

void loop() {}