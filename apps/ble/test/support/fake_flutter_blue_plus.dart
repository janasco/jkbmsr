import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';

/// A no-op [FlutterBluePlusPlatform] implementation so widget tests can mount
/// the real app on the Dart VM. Without it, `FlutterBluePlusPlatform.instance`
/// throws `UnsupportedError: flutter_blue_plus is unsupported on this
/// platform`, which the app's `initState` hits as soon as it subscribes to the
/// adapter-state stream.
///
/// Every method keeps the interface's harmless defaults (adapter unknown, no
/// devices, empty event streams), so the app renders its "disconnected" state
/// deterministically and offline.
final class FakeFlutterBluePlusPlatform extends FlutterBluePlusPlatform {}

/// Installs the fake for the current test. Call from `setUp`/`setUpAll`.
void installFakeFlutterBluePlus() {
  FlutterBluePlusPlatform.instance = FakeFlutterBluePlusPlatform();
}
