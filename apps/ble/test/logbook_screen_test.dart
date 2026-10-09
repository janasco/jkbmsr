// Logbook screen: reachable from the drawer, renders the locally stored
// history newest-first, and reveals it a page at a time rather than building
// thousands of rows at once.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/screens/logbook_screen.dart';
import 'package:jkbmsr_ble/services/logbook_store.dart';

import 'support/fake_flutter_blue_plus.dart';

Widget _wrap(Widget child) => MaterialApp(theme: ThemeData.dark(), home: child);

LogbookRecord _rec(int seconds, int code) =>
    LogbookRecord(seconds: seconds, code: code, firstSeen: DateTime.utc(2026, 1, 1));

void main() {
  setUp(installFakeFlutterBluePlus);

  testWidgets('renders stored events newest-first and only loads one page',
      (tester) async {
    final store = LogbookStore.inMemory();
    await store.merge('dev', [for (var i = 0; i < 500; i++) _rec(i, 0x01)]);

    await tester.pumpWidget(
      _wrap(LogbookScreen(store: store, deviceIdOverride: 'dev')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    // Header reports the full stored total...
    expect(find.text('500 events stored on this device'), findsOneWidget);
    // ...but the newest entry is shown while the oldest has not been paged in.
    expect(find.text('0d 00h 08m 19s'), findsOneWidget); // seconds 499
    expect(find.text('0d 00h 00m 00s'), findsNothing); // seconds 0, page 3
  });

  testWidgets('an empty store shows the honest empty state', (tester) async {
    final store = LogbookStore.inMemory();

    await tester.pumpWidget(
      _wrap(LogbookScreen(store: store, deviceIdOverride: 'dev')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.textContaining('No events stored yet'), findsOneWidget);
  });

  testWidgets('an undocumented code keeps the unknown-event path', (tester) async {
    final store = LogbookStore.inMemory();
    await store.merge('dev', [_rec(10, 0xFF)]);

    await tester.pumpWidget(
      _wrap(LogbookScreen(store: store, deviceIdOverride: 'dev')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Unknown event (0xFF)'), findsOneWidget);
  });
}
