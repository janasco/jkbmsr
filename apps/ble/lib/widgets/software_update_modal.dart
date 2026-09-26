import '../services/theme_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/self_update.dart';
import 'motion_kit.dart';

/// Live update check against the release channel
/// (api.jkbmsr.com/ble/latest.json — served from R2, latest build only).
///
/// States: checking → up-to-date | update-available (in-app download with
/// progress, then the system package installer opens over the app) |
/// installing | offline (retry).
class SoftwareUpdateModal extends StatefulWidget {
  final VoidCallback onClose;
  const SoftwareUpdateModal({super.key, required this.onClose});

  @override
  State<SoftwareUpdateModal> createState() => _SoftwareUpdateModalState();
}

enum _State { checking, upToDate, updateAvailable, playUpdateAvailable, downloading, installing, offline, failed }

class _SoftwareUpdateModalState extends State<SoftwareUpdateModal> {
  static const _latestUrl = 'https://api.jkbmsr.com/ble/latest.json';

  _State _state = _State.checking;
  String _currentVersion = '';
  String _latestVersion = '';
  String _releasedAt = '';
  bool _isPlayInstall = false;
  double _progress = 0;
  String _error = '';
  StreamSubscription<double>? _sub;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _sub?.cancel();
    SelfUpdate.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _state = _State.checking);
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(_latestUrl));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode != 200) throw const HttpException('unavailable');
      final data = jsonDecode(body) as Map<String, dynamic>;
      final latest = (data['version'] as String?) ?? '';
      if (!mounted) return;
      setState(() {
        _currentVersion = info.version;
        _latestVersion = latest;
        _releasedAt = (data['releasedAt'] as String?) ?? '';
        // Play-installed copies must update through the Play Store itself —
        // the in-app APK download is sideload-only (see SelfUpdate).
        _isPlayInstall =
            SelfUpdate.isPlayManagedInstall(info.installerStore);
        _state = _isNewer(latest, info.version)
            ? (_isPlayInstall
                ? _State.playUpdateAvailable
                : _State.updateAvailable)
            : _State.upToDate;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentVersion = info.version;
        _state = _State.offline;
      });
    }
  }

  /// Component-wise semver compare ("4.17.0" > "4.16.0"). Non-parsing
  /// versions never claim an update exists.
  bool _isNewer(String latest, String current) {
    List<int>? parse(String v) {
      final parts = v.split('.');
      if (parts.length != 3) return null;
      final n = parts.map((p) => int.tryParse(p)).toList();
      if (n.any((e) => e == null)) return null;
      return n.cast<int>();
    }

    final a = parse(latest);
    final b = parse(current);
    if (a == null || b == null) return false;
    for (int i = 0; i < 3; i++) {
      if (a[i] > b[i]) return true;
      if (a[i] < b[i]) return false;
    }
    return false;
  }

  String _fmtDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _openPlayListing() async {
    try {
      await launchUrl(
        Uri.parse(SelfUpdate.playListingUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not open Google Play.');
    }
  }

  void _startDownload() {
    setState(() {
      _state = _State.downloading;
      _progress = 0;
      _error = '';
    });
    _sub = SelfUpdate.downloadAndInstall().listen(
      (p) {
        if (mounted) setState(() => _progress = p);
      },
      onError: (Object e) {
        if (!mounted) return;
        if (e is PermissionNeeded) {
          setState(() {
            _state = _State.updateAvailable;
            _error = 'Allow "Install unknown apps" for JKBMSR BLE in the '
                'settings page that just opened, then tap Download again.';
          });
        } else {
          setState(() {
            _state = _State.failed;
            _error = e.toString();
          });
        }
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _state = _State.installing);
      },
    );
  }

  void _cancelDownload() {
    _sub?.cancel();
    SelfUpdate.cancel();
    if (mounted) setState(() => _state = _State.updateAvailable);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.bgCard(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderColor(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: StaggerIn(
          stepMs: 70,
          children: [
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.arrow_circle_up_rounded,
                    color: Color(0xFF38BDF8), size: 28),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Software Update',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context)),
            ),
            const SizedBox(height: 4),
            Text(
              'Installed: $_currentVersion',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStatus(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: const Color(0xFF090D10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _state == _State.downloading ? null : widget.onClose,
                child: Text(
                  _state == _State.downloading ? 'DOWNLOADING…' : 'CLOSE',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus() {
    switch (_state) {
      case _State.checking:
        return const Column(
          children: [
            CircularProgressIndicator(
                color: Color(0xFF38BDF8), strokeWidth: 3),
            SizedBox(height: 12),
            Text('Checking for updates…',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ],
        );
      case _State.upToDate:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2830).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You are running the latest version ($_latestVersion).',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF94A3B8), height: 1.3),
                ),
              ),
            ],
          ),
        );
      case _State.updateAvailable:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.system_update_rounded,
                      color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Version $_latestVersion is available',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context))),
                  ),
                ],
              ),
              if (_releasedAt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Released ${_fmtDate(_releasedAt)}',
                    style: const TextStyle(
                        fontSize: 11.0, color: Color(0xFF64748B))),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF090D10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: _startDownload,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('DOWNLOAD & INSTALL',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _error,
                  style: const TextStyle(
                      fontSize: 11.0, color: Color(0xFFF59E0B), height: 1.35),
                ),
              ] else ...[
                const SizedBox(height: 6),
                const Text(
                  'Downloads in-app and opens the Android installer — '
                  'no browser needed. You will confirm the install.',
                  style: TextStyle(fontSize: 11.0, color: Color(0xFF64748B)),
                ),
              ],
            ],
          ),
        );
      case _State.playUpdateAvailable:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.system_update_rounded,
                      color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Version $_latestVersion is available',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context))),
                  ),
                ],
              ),
              if (_releasedAt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Released ${_fmtDate(_releasedAt)}',
                    style: const TextStyle(
                        fontSize: 11.0, color: Color(0xFF64748B))),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF090D10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: _openPlayListing,
                  icon: const Icon(Icons.store_rounded, size: 16),
                  label: const Text('OPEN IN GOOGLE PLAY',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _error,
                  style: const TextStyle(
                      fontSize: 11.0, color: Color(0xFFF59E0B), height: 1.35),
                ),
              ] else ...[
                const SizedBox(height: 6),
                const Text(
                  'This copy was installed from Google Play, so updates '
                  'arrive through the Play Store.',
                  style: TextStyle(fontSize: 11.0, color: Color(0xFF64748B)),
                ),
              ],
            ],
          ),
        );
      case _State.downloading:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Color(0xFF38BDF8), strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Downloading v$_latestVersion… '
                      '${(_progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary(context)),
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelDownload,
                    child: const Padding(
                      padding: EdgeInsets.all(15),
                      child: Icon(Icons.close_rounded,
                          color: Color(0xFF64748B), size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _progress),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  builder: (context, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 7,
                    backgroundColor: const Color(0xFF1E2830),
                    color: const Color(0xFF38BDF8),
                  ),
                ),
              ),
            ],
          ),
        );
      case _State.installing:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user_rounded,
                  color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Download complete — Android is asking to install v$_latestVersion. '
                  'Tap Install, and the app restarts updated.',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF94A3B8), height: 1.35),
                ),
              ),
            ],
          ),
        );
      case _State.failed:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: Color(0xFFEF4444), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Update failed',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context))),
                  ),
                ],
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_error,
                    style: const TextStyle(
                        fontSize: 11.0, color: Color(0xFF94A3B8), height: 1.3)),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: BorderSide(color: AppColors.borderColor(context)),
                ),
                onPressed: _check,
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('TRY AGAIN',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      case _State.offline:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2830).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.cloud_off_rounded,
                      color: Color(0xFFF59E0B), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Could not reach the update server.',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF94A3B8))),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: BorderSide(color: AppColors.borderColor(context)),
                ),
                onPressed: _check,
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('RETRY',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
    }
  }
}
