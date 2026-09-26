import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// In-app self-update for sideloaded installs.
///
/// Downloads the latest signed APK from the release channel
/// (api.jkbmsr.com/ble/latest.apk) to the app cache and hands it to
/// Android's package installer through a FileProvider — the whole update
/// happens inside the app, no browser or download manager detour.
class SelfUpdate {
  static const _channel = MethodChannel('com.jkbmsr.ble/self_update');

  static const apkUrl = 'https://api.jkbmsr.com/ble/latest.apk';

  /// Google Play listing, used by Play-installed copies (which must update
  /// through Play itself, never via a sideloaded APK).
  static const playListingUrl =
      'https://play.google.com/store/apps/details?id=com.jkbmsr.ble';

  /// True when Android reports this copy was installed by Google Play.
  /// Play-installed copies update through Play itself; the in-app APK
  /// download below is sideload-only (Play policy forbids self-updating).
  static bool isPlayManagedInstall(String? installerStore) =>
      installerStore == 'com.android.vending';

  static HttpClient? _active;

  /// Aborts an in-flight download (the stream ends with an error).
  static void cancel() {
    _active?.close(force: true);
    _active = null;
  }

  /// Emits progress as 0.0–1.0 while downloading; completes once the
  /// system installer has been launched. Throws on any failure.
  static Stream<double> downloadAndInstall() async* {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..autoUncompress = false;
    _active = client;

    try {
      final request = await client.getUrl(Uri.parse(apkUrl));
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('Download failed (HTTP ${response.statusCode})');
      }

      final total = response.contentLength;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/jkbmsr-ble-update.apk');
      final sink = file.openWrite();

      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) yield received / total;
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (total > 0 && received < total) {
        throw const HttpException('Download incomplete');
      }

      final ok = await _channel
          .invokeMethod<bool>('installApk', {'path': file.path});
      if (ok != true) {
        // False means the unknown-sources permission was missing and the
        // OS settings page was opened instead — not a hard failure.
        throw const PermissionNeeded();
      }
    } finally {
      _active = null;
      client.close();
    }
  }
}

/// The user must allow "Install unknown apps" for this app first; the
/// native side already opened the exact settings page for it.
class PermissionNeeded implements Exception {
  const PermissionNeeded();
}
