/// Re-decodes a donated contribution's raw frames and checks them against the
/// samples the app claimed.
///
/// This is the triage step the pipeline was missing. A contribution is ~100 KB of
/// bytes plus a decoded summary, and until something re-decoded the bytes there
/// was no way to tell a faithful capture from a corrupt one without reading frames
/// by hand — which is why every capture sat unreviewed.
///
/// What it proves: the bytes in the payload really do decode, with this parser, to
/// the numbers the app reported. It cannot prove the pack was healthy.
///
/// Usage:
///   dart run tool/verify_contribution.dart /tmp/contribution.json
///
/// Exit 0 = every cell-info frame decodes and agrees; 1 = a mismatch.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bms_core/bms_core.dart';

/// Tolerances: the payload carries the same doubles the parser produced, so these
/// only absorb JSON round-tripping, not a disagreement.
const double _voltTolerance = 0.01;
const double _ampTolerance = 0.1;
const double _tempTolerance = 0.5;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: verify_contribution.dart <contribution.json>');
    exit(2);
  }

  final doc = jsonDecode(File(args.first).readAsStringSync()) as Map<String, dynamic>;
  final bms = (doc['bms'] as Map?)?.cast<String, dynamic>() ?? const {};
  final frames = (doc['rawFrames'] as List? ?? const []).cast<Map<String, dynamic>>();
  final samples = (doc['samples'] as List? ?? const []).cast<Map<String, dynamic>>();
  final is32s = bms['layout'] == 'JK02_32S';

  final byType = <String, int>{};
  for (final frame in frames) {
    final type = '${frame['frameType']}';
    byType[type] = (byType[type] ?? 0) + 1;
  }

  // A donor may switch fields off in the review screen. Those are ABSENT BY
  // CHOICE, not a mismatch — one real contribution omitted its model name, and a
  // verifier that called that a failure would report the privacy control as a
  // defect.
  final omitted = ((doc['redaction'] as Map?)?['omittedFields'] as List? ?? const [])
      .map((field) => '$field')
      .toSet();
  bool omittedField(String id) => omitted.contains(id);

  final problems = <String>[];

  // Identity: the device-info frame is what the BMS says it is.
  final deviceFrames = frames.where((f) => f['frameType'] == 'deviceInfo').toList();
  if (deviceFrames.isNotEmpty) {
    final info = BmsProtocolHelper.parseJk02DeviceInfoFrame(_bytes('${deviceFrames.first['hex']}'));
    if (info == null) {
      problems.add('deviceInfo frame did not decode');
    } else {
      if (!omittedField('bms.modelName') && info.modelName != bms['modelName']) {
        problems.add('model: frame=${info.modelName} payload=${bms['modelName']}');
      }
      if (!omittedField('bms.hardwareVersion') &&
          info.hardwareVersion != bms['hardwareVersion']) {
        problems.add('hardware: frame=${info.hardwareVersion} payload=${bms['hardwareVersion']}');
      }
      if (!omittedField('bms.softwareVersion') &&
          info.softwareVersion != bms['softwareVersion']) {
        problems.add('firmware: frame=${info.softwareVersion} payload=${bms['softwareVersion']}');
      }
    }
  } else {
    problems.add('no deviceInfo frame');
  }

  // Telemetry: each cell-info frame is the source of the sample at the same index.
  final cellFrames = frames.where((f) => f['frameType'] == 'cellInfo').toList();
  if (cellFrames.length != samples.length) {
    problems.add('${cellFrames.length} cellInfo frames but ${samples.length} samples');
  }
  final count = cellFrames.length < samples.length ? cellFrames.length : samples.length;
  var decoded = 0;
  var cellsChecked = 0;

  void close(String what, num got, num want, double tolerance, int index) {
    if ((got - want).abs() > tolerance) {
      problems.add('sample $index $what: frame=$got payload=$want');
    }
  }

  for (var i = 0; i < count; i++) {
    final status = BmsProtocolHelper.parseJk02CellInfoFrame(
      _bytes('${cellFrames[i]['hex']}'),
      is32s: is32s,
    );
    if (status == null) {
      problems.add('sample $i: cellInfo frame did not decode');
      continue;
    }
    decoded++;
    final sample = samples[i];
    close('voltage', status.totalVoltage, sample['voltageV'] as num, _voltTolerance, i);
    close('current', status.currentA, sample['currentA'] as num, _ampTolerance, i);
    close('soc', status.soc, sample['socPct'] as num, 0, i);
    close('mosTemp', status.mosTemp, sample['mosTempC'] as num, _tempTolerance, i);
    close('t1', status.t1Temp, sample['temp1C'] as num, _tempTolerance, i);
    close('t2', status.t2Temp, sample['temp2C'] as num, _tempTolerance, i);

    final claimed = (sample['cellVoltagesV'] as List? ?? const []).cast<num>();
    if (claimed.length != status.cells.length) {
      problems.add('sample $i: ${status.cells.length} cells decoded, ${claimed.length} in payload');
      continue;
    }
    for (var c = 0; c < claimed.length; c++) {
      close('cell ${c + 1}', status.cells[c].voltage, claimed[c], _voltTolerance, i);
      cellsChecked++;
    }
  }

  print('  app / captured  : ${(doc['app'] as Map?)?['version']}  ${doc['capturedAt']}');
  print('  model / layout  : ${bms['modelName']}  ${bms['layout']}  '
      '${bms['hardwareVersion']}/${bms['softwareVersion']}');
  print('  frames          : ${frames.length}  $byType');
  print('  samples         : ${samples.length}   decoded $decoded   cells $cellsChecked');
  print('  omitted fields  : ${omitted.isEmpty ? 'none' : omitted.join(', ')}');
  print('  logbook         : '
      '${doc['logbook'] == null ? 'absent' : '${((doc['logbook'] as Map)['entries'] as List? ?? const []).length} entries'}');

  if (problems.isEmpty) {
    print('  VERDICT         : OK — every frame decodes to what the app reported');
    exit(0);
  }
  print('  VERDICT         : FAILED (${problems.length})');
  for (final problem in problems.take(12)) {
    print('    - $problem');
  }
  exit(1);
}

List<int> _bytes(String hex) {
  final out = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}
