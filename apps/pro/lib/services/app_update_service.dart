import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Checks the public release endpoint for a newer app build than the one
/// installed. The endpoint is written by the release pipeline
/// (scripts/publish-release.sh → api.jkbmsr.com/mobile/latest.json), so it
/// always reflects the newest published version.
class AppUpdateService {
  static const String latestJsonUrl = 'https://api.jkbmsr.com/mobile/latest.json';
  static const String downloadUrl = 'https://api.jkbmsr.com/mobile/latest.apk';

  /// Returns the newer version string when an update is available, else null.
  /// Never throws — a network failure just means "no prompt".
  static Future<String?> updateAvailable() async {
    try {
      final installed = (await PackageInfo.fromPlatform()).version;
      final response = await http
          .get(Uri.parse(latestJsonUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = body['version'] as String?;
      if (latest == null || latest.isEmpty) return null;
      return _isNewer(latest, installed) ? latest : null;
    } catch (_) {
      return null;
    }
  }

  static bool _isNewer(String latest, String installed) {
    final a = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final b = installed.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
