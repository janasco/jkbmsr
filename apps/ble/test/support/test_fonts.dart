import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registers a real monospace face as the `monospace` family for widget tests.
///
/// The app renders every numeric value with `fontFamily: 'monospace'`. Android
/// resolves that generic name; the Flutter test engine does not, so those
/// values fall back to its placeholder font, whose advance is about twice a
/// normal face's and which has no glyph for `Ω`. That turns a healthy tile into
/// a two-line value and then into a layout overflow a real device does not
/// have - and makes a width assertion measure the wrong font.
///
/// The face is the build host's DejaVu Sans Mono, the same one the
/// store-screenshot generator registers. A missing file fails the test rather
/// than silently restoring the phantom this exists to remove.
///
/// The app's body family (`PlusJakartaSans`) is deliberately not registered
/// here: in `flutter test` it resolves to the placeholder font, which is
/// *wider* than the real face, so a layout that fits in the test also fits on a
/// device. That direction is safe; the missing glyph was not.
Future<void> loadMonospaceTestFont() async {
  const candidates = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf',
  ];

  final loader = FontLoader('monospace');
  var loaded = 0;
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(
      Future.value(
        ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync())),
      ),
    );
    loaded++;
  }
  if (loaded == 0) {
    fail('no monospace font found on this host; the overflow measurement '
        'would be using the test placeholder and would not mean anything');
  }
  await loader.load();
}
