#include <Arduino.h>
#include <unity.h>

#include "bms/BasenBmsDecoder.h"

using namespace jkbmsr;

// Synthetic Basen frames, hand-built to match the documented envelope
// (SOF 0x3A, addr 0x16, func, len, payload, plain-16-bit-sum checksum LE,
// 0D 0A trailer — all telemetry values little-endian). Not real device
// captures — see devices/BASEN_BLE/fixtures/README.md.
//
// Status (0x2A) decoded values: 51.20V, +12.0A, 614.4W, 180.0Ah remaining,
// 82% SOC, temps 25C/26C/35C, charging on / discharging off, error 1. The
// cell chunk (0x24) puts 12 cells 3.300..3.306V (avg over the 12 =
// 3.3019167V). Every decoded value was computed by an independent Python
// script before use.
static const uint8_t kBasenStatusFrame[] = {
    0x3A, 0x16, 0x2A, 0x15, 0xE0, 0x2E, 0x00, 0x00, 0x00, 0xC8, 0x00, 0x00, 0x19, 0x1A, 0x00, 0x23,
    0x20, 0xBF, 0x02, 0x00, 0x80, 0x00, 0x01, 0x00, 0x52, 0x35, 0x04, 0x0D, 0x0A,
};

static const uint8_t kBasenCellChunk1_12[] = {
    0x3A, 0x16, 0x24, 0x18, 0xE4, 0x0C, 0xEE, 0x0C, 0xDA, 0x0C, 0xE9, 0x0C, 0xD0, 0x0C, 0xF3, 0x0C,
    0xDF, 0x0C, 0xE4, 0x0C, 0xF0, 0x0C, 0xEC, 0x0C, 0xE6, 0x0C, 0xEA, 0x0C, 0xA9, 0x0B, 0x0D, 0x0A,
};

// General Info (0x2B): 200.0Ah nominal capacity, 198.0Ah real capacity,
// 42 cycles.
static const uint8_t kBasenGeneralInfoFrame[] = {
    0x3A, 0x16, 0x2B, 0x18, 0x40, 0x0D, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x70, 0x05, 0x03, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2A, 0x00, 0x4B, 0x01, 0x0D, 0x0A,
};

void test_parse_status_frame() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(
      BasenBmsDecoder::parseStatusFrame(kBasenStatusFrame, sizeof(kBasenStatusFrame), t));
  TEST_ASSERT_EQUAL_UINT8(4, t.temperatureSensorCount);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 51.2f, t.packVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 12.0f, t.packCurrent);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 614.4f, t.power);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 180.0f, t.remainingCapacityAh);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 82.0f, t.stateOfCharge);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 25.0f, t.temperature1);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 26.0f, t.temperature2);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 35.0f, t.mosfetTemperature);
  TEST_ASSERT_TRUE(t.chargingEnabled);
  TEST_ASSERT_FALSE(t.dischargingEnabled);
  TEST_ASSERT_EQUAL_UINT32(1, t.errorsBitmask);
  TEST_ASSERT_EQUAL_STRING("ble", t.source);
  TEST_ASSERT_TRUE(t.valid);
}

void test_parse_cell_chunk() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(
      BasenBmsDecoder::parseCellChunkFrame(kBasenCellChunk1_12, sizeof(kBasenCellChunk1_12), t));
  TEST_ASSERT_EQUAL_UINT8(12, t.cellCount);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.300f, t.cellVoltages[0]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.310f, t.cellVoltages[1]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.290f, t.cellVoltages[2]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.305f, t.cellVoltages[3]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.280f, t.cellVoltages[4]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.315f, t.cellVoltages[5]);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.315f, t.maxCellVoltage);
  TEST_ASSERT_EQUAL_UINT8(6, t.maxVoltageCell);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.280f, t.minCellVoltage);
  TEST_ASSERT_EQUAL_UINT8(5, t.minVoltageCell);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 0.035f, t.deltaCellVoltage);
  TEST_ASSERT_FLOAT_WITHIN(0.0001f, 3.3019167f, t.avgCellVoltage);
  TEST_ASSERT_TRUE(t.valid);
}

void test_parse_general_info() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(BasenBmsDecoder::parseGeneralInfoFrame(
      kBasenGeneralInfoFrame, sizeof(kBasenGeneralInfoFrame), t));
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 200.0f, t.fullCapacityAh);
  TEST_ASSERT_EQUAL_UINT32(42, t.cycleCount);
  // General info does not mark a sample valid on its own (client gates it on
  // the status frame first).
  TEST_ASSERT_EQUAL_STRING("ble", t.source);
}

void test_frame_complete_length() {
  // Header alone reports the full envelope length reliably.
  TEST_ASSERT_EQUAL_UINT(sizeof(kBasenStatusFrame),
                         BasenBmsDecoder::frameCompleteLength(kBasenStatusFrame,
                                                              sizeof(kBasenStatusFrame)));
  // A partial prefix (SOF + addr + func + len only) is not complete yet.
  TEST_ASSERT_EQUAL_UINT(0, BasenBmsDecoder::frameCompleteLength(kBasenStatusFrame, 4));
  // Corrupted trailer is not complete.
  uint8_t frame[sizeof(kBasenStatusFrame)];
  memcpy(frame, kBasenStatusFrame, sizeof(frame));
  frame[sizeof(frame) - 1] = 0x00;
  TEST_ASSERT_EQUAL_UINT(0, BasenBmsDecoder::frameCompleteLength(frame, sizeof(frame)));
}

void test_build_request_frame() {
  uint8_t frame[BasenBmsDecoder::kMaxRequestFrameSize];
  BasenBmsDecoder::buildRequestFrame(frame, BasenBmsDecoder::kFrameTypeStatus);
  TEST_ASSERT_EQUAL_HEX8(0x3A, frame[0]);
  TEST_ASSERT_EQUAL_HEX8(0x16, frame[1]);
  TEST_ASSERT_EQUAL_HEX8(0x2A, frame[2]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[3]);
  // Plain sum over frame[1..3] == 0x16+0x2A+0x00 = 0x40.
  TEST_ASSERT_EQUAL_HEX8(0x40, frame[4]);
  TEST_ASSERT_EQUAL_HEX8(0x00, frame[5]);
  TEST_ASSERT_EQUAL_HEX8(0x0D, frame[6]);
  TEST_ASSERT_EQUAL_HEX8(0x0A, frame[7]);
}

void test_rejects_bad_checksum() {
  uint8_t frame[sizeof(kBasenStatusFrame)];
  memcpy(frame, kBasenStatusFrame, sizeof(frame));
  frame[sizeof(frame) - 4] ^= 0xFF;  // flip a checksum byte
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(BasenBmsDecoder::parseStatusFrame(frame, sizeof(frame), t));
}

void test_rejects_wrong_function() {
  uint8_t frame[sizeof(kBasenStatusFrame)];
  memcpy(frame, kBasenStatusFrame, sizeof(frame));
  frame[2] = 0x2B;  // general info, not status
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(BasenBmsDecoder::parseStatusFrame(frame, sizeof(frame), t));
}

// Regression: an oversized cell-chunk frame must be rejected, not decoded.
//
// frame[3] is the declared payload length and is fully radio-controlled.
// A well-formed envelope declaring length 120 (0x78) yields cellsInFrame=60,
// which before the bound in parseCellChunkFrame wrote
// telemetry.cellVoltages[12..71] — 160 bytes past the end of the 32-element
// array, walking through cellCount, wireResistanceOhms[] and into the
// BatteryTelemetry String internals. The checksum below is computed over the
// real frame so this exercises the accepted path, not an early rejection.
static void test_rejects_oversized_cell_chunk() {
  uint8_t frame[128];
  memset(frame, 0xE4, sizeof(frame));
  frame[0] = 0x3A;
  frame[1] = 0x16;
  frame[2] = BasenBmsDecoder::kFrameTypeCellVoltages13_24;  // base offset 12
  frame[3] = 120;                                            // 60 cells claimed
  const size_t frameLen = 4 + 120 + 4;                      // == 128
  frame[frameLen - 2] = 0x0D;
  frame[frameLen - 1] = 0x0A;
  // Plain 16-bit sum over frame[1 .. 3+dataLen], as validateChecksum does.
  uint32_t sum = 0;
  for (size_t i = 1; i <= 3 + 120; ++i) {
    sum += frame[i];
  }
  frame[frameLen - 4] = static_cast<uint8_t>(sum & 0xFF);
  frame[frameLen - 3] = static_cast<uint8_t>((sum >> 8) & 0xFF);

  // The frame is structurally complete and checksum-valid ...
  TEST_ASSERT_EQUAL_UINT(frameLen,
                         BasenBmsDecoder::frameCompleteLength(frame, frameLen));
  // ... but must still be refused, and must not touch the telemetry array.
  BatteryTelemetry t;
  TEST_ASSERT_FALSE(BasenBmsDecoder::parseCellChunkFrame(frame, frameLen, t));
  TEST_ASSERT_EQUAL_UINT8(0, t.cellCount);
  TEST_ASSERT_EQUAL_UINT8(0, t.maxVoltageCell);
  TEST_ASSERT_FALSE(t.valid);
}

// A chunk that exactly fills its 12 cells is still accepted, so the bound
// above cannot be tightened into a regression.
static void test_accepts_maximum_legitimate_chunk() {
  BatteryTelemetry t;
  TEST_ASSERT_TRUE(BasenBmsDecoder::parseCellChunkFrame(kBasenCellChunk1_12,
                                                        sizeof(kBasenCellChunk1_12), t));
  TEST_ASSERT_EQUAL_UINT8(12, t.cellCount);
}

void setup() {
  delay(2000);
  UNITY_BEGIN();
  RUN_TEST(test_parse_status_frame);
  RUN_TEST(test_parse_cell_chunk);
  RUN_TEST(test_parse_general_info);
  RUN_TEST(test_frame_complete_length);
  RUN_TEST(test_build_request_frame);
  RUN_TEST(test_rejects_bad_checksum);
  RUN_TEST(test_rejects_wrong_function);
  RUN_TEST(test_rejects_oversized_cell_chunk);
  RUN_TEST(test_accepts_maximum_legitimate_chunk);
  UNITY_END();
}

void loop() {}