/// Reports which cell-info frame in a captured payload fails to decode, and why.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bms_core/bms_core.dart';

void main(List<String> args) {
  final raw = jsonDecode(File(args.first).readAsStringSync()) as Map<String, dynamic>;
  final frames = (raw['rawFrames'] as List).cast<Map<String, dynamic>>();
  final is32s = (raw['bms']?['layout'] as String? ?? '') == 'JK02_32S';

  var index = 0;
  for (final frame in frames) {
    if (frame['frameType'] != 'cellInfo') continue;
    final hex = (frame['hex'] as String).replaceAll(' ', '');
    final bytes = <int>[
      for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    final ok = BmsProtocolHelper.parseJk02CellInfoFrame(bytes, is32s: is32s) != null;
    if (!ok) {
      final head = bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('  frame #$index FAILS  len=${bytes.length}  head=$head  cmd=0x${bytes[4].toRadixString(16)}');
    }
    index++;
  }
  print('  cellInfo frames: $index');
}
