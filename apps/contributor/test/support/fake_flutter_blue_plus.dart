import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';

/// A no-op [FlutterBluePlusPlatform] so widget tests can mount the app on the
/// Dart VM, where flutter_blue_plus has no platform implementation. Every
/// method keeps the interface's harmless defaults (adapter unknown, no
/// devices, empty streams). Same arrangement as `apps/ble`'s test support.
final class FakeFlutterBluePlusPlatform extends FlutterBluePlusPlatform {}

/// Installs the fake for the current test.
void installFakeFlutterBluePlus() {
  FlutterBluePlusPlatform.instance = FakeFlutterBluePlusPlatform();
}
