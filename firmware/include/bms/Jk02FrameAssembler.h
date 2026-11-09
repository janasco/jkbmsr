#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

/// Reassembles JK02 frames from BLE notification fragments.
///
/// Reassembly is over the **byte stream**, not over notification boundaries.
/// This is not hypothetical: a real JK-PB1A16S15P (hw 15A / sw 15.30) sends
/// `AT\r\nAT\r\n` ahead of the frame on the same characteristic, so a frame can
/// start at any offset inside a fragment.
///
/// The previous logic only resynced when a *notification* began with the magic,
/// then took the first 300-byte window regardless of where the frame actually
/// started. With an 8-byte prefix it therefore declared an intact frame a
/// `header/checksum mismatch` and discarded it — one wasted error per frame, and
/// no telemetry from a device that prefixes every frame.
///
/// Pure and header-only on purpose: it has no radio, no Arduino and no clock, so
/// it is exercised on the host by test/test_jk02_frame_assembler.
class Jk02FrameAssembler {
 public:
  static constexpr size_t kFrameSize = 300;
  static constexpr size_t kMagicSize = 4;
  /// Four full frames plus a partial magic. One frame is not enough and two is
  /// only just enough: a BLE notification can carry ~512 bytes at a negotiated
  /// MTU (a whole frame plus most of the next), and a caller may hand over
  /// concatenated frames plus junk in one feed. A single feed is therefore
  /// assumed to be at most this; anything larger keeps only its tail, which is
  /// the honest bound rather than an unbounded buffer. The client drains after
  /// every notification, so in practice it never approaches this.
  static constexpr size_t kBufferSize = kFrameSize * 4 + kMagicSize;

  void reset() { length_ = 0; }

  size_t buffered() const { return length_; }

  /// Feeds one notification fragment.
  void feed(const uint8_t* data, size_t length) {
    if (data == nullptr || length == 0) {
      return;
    }
    if (length >= kBufferSize) {
      // Nothing already buffered can survive a fragment this large.
      data += length - kBufferSize;
      length = kBufferSize;
      length_ = 0;
    }
    if (length_ + length > kBufferSize) {
      const size_t drop = length_ + length - kBufferSize;
      std::memmove(buffer_, buffer_ + drop, length_ - drop);
      length_ -= drop;
    }
    std::memcpy(buffer_ + length_, data, length);
    length_ += length;
  }

  /// The next complete frame candidate, or nullptr when more bytes are needed.
  ///
  /// Any bytes before the magic are discarded first, so a returned frame always
  /// begins at offset 0 with `55 AA EB 90`. Validity is the CALLER's check: the
  /// assembler knows where frames start, not whether they are intact.
  const uint8_t* peekFrame() {
    size_t start = 0;
    while (start + kMagicSize <= length_) {
      if (buffer_[start] == 0x55 && buffer_[start + 1] == 0xAA &&
          buffer_[start + 2] == 0xEB && buffer_[start + 3] == 0x90) {
        break;
      }
      ++start;
    }
    if (start > 0) {
      consume(start);
    }
    if (length_ < kFrameSize) {
      return nullptr;
    }
    return buffer_;
  }

  /// Drops the frame returned by the last peekFrame().
  void consumeFrame() { consume(kFrameSize); }

  /// Drops one byte, for resyncing after a candidate failed its checksum.
  void skipByte() { consume(1); }

 private:
  void consume(size_t count) {
    if (count >= length_) {
      length_ = 0;
      return;
    }
    std::memmove(buffer_, buffer_ + count, length_ - count);
    length_ -= count;
  }

  uint8_t buffer_[kBufferSize] = {};
  size_t length_ = 0;
};
