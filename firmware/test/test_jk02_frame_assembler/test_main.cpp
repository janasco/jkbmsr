#include <Arduino.h>
#include <unity.h>

#include <cstring>

#include "bms/Jk02Decoder.h"
#include "bms/Jk02FrameAssembler.h"

// Reassembly over the byte stream, not over notification boundaries.
//
// The case that made this a real defect: a JK-PB1A16S15P (hw 15A / sw 15.30)
// sends "AT\r\nAT\r\n" ahead of the frame on the same BLE characteristic. The
// old code only resynced when a *notification* started with the magic and then
// took a fixed 300-byte window from offset 0, so it logged an intact frame as a
// header/checksum mismatch and discarded it.

namespace {

constexpr size_t kFrame = Jk02FrameAssembler::kFrameSize;

void makeFrame(uint8_t* out, uint8_t type, uint8_t fill) {
  out[0] = 0x55;
  out[1] = 0xAA;
  out[2] = 0xEB;
  out[3] = 0x90;
  out[4] = type;
  for (size_t i = 5; i < kFrame - 1; i++) {
    out[i] = fill;
  }
  out[kFrame - 1] = 0x00;  // checksum byte: the assembler does not validate it
}

void feedInChunks(Jk02FrameAssembler& assembler, const uint8_t* data, size_t length, size_t chunk) {
  for (size_t offset = 0; offset < length; offset += chunk) {
    const size_t take = (offset + chunk > length) ? (length - offset) : chunk;
    assembler.feed(data + offset, take);
  }
}

}  // namespace

void test_ignores_the_echoed_command_between_two_frames() {
  // Shape captured from a real JK-PB1A16S15P (hw 11A / sw 11.55) on 2026-11-10:
  // frame, then the gateway's own 0xC8 read command echoed back with the magic
  // REVERSED (AA 55 90 EB), then the next frame. The reversed magic is what makes
  // this safe to resync through: it cannot be read as a frame start, so the
  // scanner walks past it and finds the real header after.
  uint8_t first[kFrame];
  uint8_t second[kFrame];
  makeFrame(first, 0x03, 0x11);
  makeFrame(second, 0x02, 0x22);

  uint8_t stream[2 * kFrame + 24];
  size_t at = 0;
  memcpy(stream + at, first, kFrame);
  at += kFrame;
  stream[at++] = 0x50;                       // trailing byte of the frame above
  stream[at++] = 0xAA;                       // echoed command, magic reversed
  stream[at++] = 0x55;
  stream[at++] = 0x90;
  stream[at++] = 0xEB;
  stream[at++] = 0xC8;
  stream[at++] = 0x01;
  stream[at++] = 0x01;
  for (int i = 0; i < 12; i++) stream[at++] = 0x00;
  stream[at++] = 0x44;
  memcpy(stream + at, second, kFrame);
  at += kFrame;

  Jk02FrameAssembler assembler;
  feedInChunks(assembler, stream, at, 20);

  const uint8_t* assembled = assembler.peekFrame();
  TEST_ASSERT_NOT_NULL(assembled);
  TEST_ASSERT_EQUAL_HEX8(0x03, assembled[4]);
  TEST_ASSERT_EQUAL_MEMORY(first, assembled, kFrame);
  assembler.consumeFrame();

  const uint8_t* next = assembler.peekFrame();
  TEST_ASSERT_NOT_NULL(next);
  TEST_ASSERT_EQUAL_HEX8(0x02, next[4]);
  TEST_ASSERT_EQUAL_MEMORY(second, next, kFrame);
}

void test_a_reversed_magic_alone_never_starts_a_frame() {
  // The echo starts AA 55 90 EB. A scanner that looked for the header without
  // the 0x55-first ordering would treat it as a frame and then fail the checksum
  // on whatever followed, which is exactly the noise the field log was full of.
  static const uint8_t kEchoOnly[8] = {0xAA, 0x55, 0x90, 0xEB, 0xC8, 0x01, 0x01, 0x00};
  Jk02FrameAssembler assembler;
  assembler.feed(kEchoOnly, sizeof(kEchoOnly));
  TEST_ASSERT_NULL(assembler.peekFrame());
}

void test_reassembles_a_clean_frame_from_20_byte_fragments() {
  uint8_t frame[kFrame];
  makeFrame(frame, 0x02, 0xA5);

  Jk02FrameAssembler assembler;
  feedInChunks(assembler, frame, kFrame, 20);

  const uint8_t* assembled = assembler.peekFrame();
  TEST_ASSERT_NOT_NULL(assembled);
  TEST_ASSERT_EQUAL_HEX8(0x02, assembled[4]);
  TEST_ASSERT_EQUAL_MEMORY(frame, assembled, kFrame);
}

void test_resyncs_a_frame_prefixed_with_at_commands() {
  // Exactly the reported shape: 8 bytes of "AT\r\nAT\r\n" then the frame.
  static const uint8_t kPrefix[8] = {'A', 'T', '\r', '\n', 'A', 'T', '\r', '\n'};
  uint8_t frame[kFrame];
  makeFrame(frame, 0x03, 0x5A);

  uint8_t buffer[8 + kFrame];
  std::memcpy(buffer, kPrefix, sizeof(kPrefix));
  std::memcpy(buffer + sizeof(kPrefix), frame, kFrame);

  Jk02FrameAssembler assembler;
  feedInChunks(assembler, buffer, sizeof(buffer), 20);

  const uint8_t* assembled = assembler.peekFrame();
  TEST_ASSERT_NOT_NULL(assembled);
  TEST_ASSERT_EQUAL_HEX8(0x55, assembled[0]);
  TEST_ASSERT_EQUAL_HEX8(0xAA, assembled[1]);
  TEST_ASSERT_EQUAL_HEX8(0xEB, assembled[2]);
  TEST_ASSERT_EQUAL_HEX8(0x90, assembled[3]);
  TEST_ASSERT_EQUAL_MEMORY(frame, assembled, kFrame);
}

void test_returns_two_frames_from_one_feed() {
  uint8_t first[kFrame];
  uint8_t second[kFrame];
  makeFrame(first, 0x02, 0x11);
  makeFrame(second, 0x01, 0x22);

  uint8_t buffer[2 * kFrame];
  std::memcpy(buffer, first, kFrame);
  std::memcpy(buffer + kFrame, second, kFrame);

  Jk02FrameAssembler assembler;
  assembler.feed(buffer, sizeof(buffer));

  const uint8_t* a = assembler.peekFrame();
  TEST_ASSERT_NOT_NULL(a);
  TEST_ASSERT_EQUAL_HEX8(0x02, a[4]);
  assembler.consumeFrame();

  const uint8_t* b = assembler.peekFrame();
  TEST_ASSERT_NOT_NULL(b);
  TEST_ASSERT_EQUAL_HEX8(0x01, b[4]);
  assembler.consumeFrame();

  TEST_ASSERT_NULL(assembler.peekFrame());
}

void test_junk_between_frames_is_dropped() {
  static const uint8_t kJunk[5] = {0x00, 0xFF, 'A', 'T', '\n'};
  uint8_t first[kFrame];
  uint8_t second[kFrame];
  makeFrame(first, 0x02, 0x33);
  makeFrame(second, 0x05, 0x44);

  uint8_t buffer[2 * kFrame + sizeof(kJunk)];
  std::memcpy(buffer, first, kFrame);
  std::memcpy(buffer + kFrame, kJunk, sizeof(kJunk));
  std::memcpy(buffer + kFrame + sizeof(kJunk), second, kFrame);

  Jk02FrameAssembler assembler;
  assembler.feed(buffer, sizeof(buffer));

  const uint8_t* a = assembler.peekFrame();
  TEST_ASSERT_NOT_NULL(a);
  TEST_ASSERT_EQUAL_HEX8(0x02, a[4]);
  assembler.consumeFrame();

  const uint8_t* b = assembler.peekFrame();
  TEST_ASSERT_NOT_NULL(b);
  TEST_ASSERT_EQUAL_HEX8(0x05, b[4]);
}

void test_junk_without_a_magic_yields_nothing_and_stays_bounded() {
  uint8_t junk[1000];
  std::memset(junk, 0xA5, sizeof(junk));

  Jk02FrameAssembler assembler;
  assembler.feed(junk, sizeof(junk));

  TEST_ASSERT_NULL(assembler.peekFrame());
  // Only a partial magic can still become a frame start.
  TEST_ASSERT_TRUE(assembler.buffered() <= Jk02FrameAssembler::kMagicSize - 1);
}

void test_an_oversized_feed_keeps_the_tail() {
  uint8_t frame[kFrame];
  makeFrame(frame, 0x02, 0x66);

  // 400 bytes of junk and then the frame, in ONE notification: the assembler must
  // keep the tail, not discard everything because the buffer overflowed.
  uint8_t buffer[400 + kFrame];
  std::memset(buffer, 0x00, 400);
  std::memcpy(buffer + 400, frame, kFrame);

  Jk02FrameAssembler assembler;
  assembler.feed(buffer, sizeof(buffer));

  const uint8_t* assembled = assembler.peekFrame();
  TEST_ASSERT_NOT_NULL(assembled);
  TEST_ASSERT_EQUAL_MEMORY(frame, assembled, kFrame);
}

void test_reset_clears_a_partial_frame() {
  uint8_t frame[kFrame];
  makeFrame(frame, 0x02, 0x77);

  Jk02FrameAssembler assembler;
  assembler.feed(frame, 100);
  TEST_ASSERT_EQUAL_UINT32(100, assembler.buffered());

  assembler.reset();
  TEST_ASSERT_EQUAL_UINT32(0, assembler.buffered());
  assembler.feed(frame + 100, kFrame - 100);
  TEST_ASSERT_NULL(assembler.peekFrame());
}


/// The exact shape from a real gateway log (JK-PB1A16S15P, hw 15A, fw 0.9.9):
/// the gateway's own 0xC8 read command echoed back, then "AT\r\n", then the
/// settings frame. Note the echo begins `AA 55 90 EB` - the magic reversed - so
/// it must not be mistaken for a frame start, and the real frame begins 25 bytes
/// in. The frame body is from that device's donated contribution.
void test_echoed_command_and_at_prefix_still_yield_the_frame() {
  static const uint8_t kPrefix[] = {
      0xAA, 0x55, 0x90, 0xEB, 0xC8, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x44, 0x41, 0x54, 0x0D, 0x0A,
  };
  static const uint8_t kSettings[] = {
      0x55, 0xAA, 0xEB, 0x90, 0x01, 0x89, 0xC4, 0x09, 0x00, 0x00, 0xF0, 0x0A,
      0x00, 0x00, 0x55, 0x0B, 0x00, 0x00, 0x10, 0x0E, 0x00, 0x00, 0x98, 0x0D,
      0x00, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x99, 0x0D, 0x00, 0x00, 0x54, 0x0B,
      0x00, 0x00, 0xC5, 0x0D, 0x00, 0x00, 0xF6, 0x09, 0x00, 0x00, 0x5A, 0x0A,
      0x00, 0x00, 0x48, 0xE8, 0x01, 0x00, 0x03, 0x00, 0x00, 0x00, 0x3C, 0x00,
      0x00, 0x00, 0x48, 0xE8, 0x01, 0x00, 0x2C, 0x01, 0x00, 0x00, 0x3C, 0x00,
      0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0xB6, 0x03, 0x00, 0x00, 0xBC, 0x02,
      0x00, 0x00, 0x58, 0x02, 0x00, 0x00, 0xBC, 0x02, 0x00, 0x00, 0x58, 0x02,
      0x00, 0x00, 0x14, 0x00, 0x00, 0x00, 0x46, 0x00, 0x00, 0x00, 0x20, 0x03,
      0x00, 0x00, 0xBC, 0x02, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x01, 0x00,
      0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x20, 0x95,
      0x09, 0x00, 0xDC, 0x05, 0x00, 0x00, 0x34, 0x0D, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x60, 0xE3, 0x16, 0x00, 0x10, 0x32, 0x3C, 0x32, 0x18, 0xFE,
      0xFF, 0xFF, 0xFF, 0x9F, 0xE9, 0x1D, 0x02, 0x00, 0x00, 0x00, 0x00, 0x13,
  };

  uint8_t stream[sizeof(kPrefix) + sizeof(kSettings)];
  std::memcpy(stream, kPrefix, sizeof(kPrefix));
  std::memcpy(stream + sizeof(kPrefix), kSettings, sizeof(kSettings));

  Jk02FrameAssembler assembler;
  feedInChunks(assembler, stream, sizeof(stream), 20);

  const uint8_t* frame = assembler.peekFrame();
  TEST_ASSERT_NOT_NULL(frame);
  TEST_ASSERT_EQUAL_HEX8(0x01, frame[4]);
  TEST_ASSERT_TRUE(jkbmsr::jk02FrameValid(frame, kFrame));
  TEST_ASSERT_EQUAL_MEMORY(kSettings, frame, kFrame);
}

void setup() {
  delay(2000);
  UNITY_BEGIN();
  RUN_TEST(test_ignores_the_echoed_command_between_two_frames);
  RUN_TEST(test_a_reversed_magic_alone_never_starts_a_frame);
  RUN_TEST(test_reassembles_a_clean_frame_from_20_byte_fragments);
  RUN_TEST(test_resyncs_a_frame_prefixed_with_at_commands);
  RUN_TEST(test_returns_two_frames_from_one_feed);
  RUN_TEST(test_junk_between_frames_is_dropped);
  RUN_TEST(test_junk_without_a_magic_yields_nothing_and_stays_bounded);
  RUN_TEST(test_an_oversized_feed_keeps_the_tail);
  RUN_TEST(test_reset_clears_a_partial_frame);
  RUN_TEST(test_echoed_command_and_at_prefix_still_yield_the_frame);
  UNITY_END();
}

void loop() {}
