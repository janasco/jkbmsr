import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ble_service.dart';
import '../services/logbook_store.dart';
import '../widgets/motion_kit.dart';

/// The BMS logbook, moved out of the Status tab and into its own drawer screen.
///
/// The hardware only ever returns a bounded window per fetch (see
/// [LogbookStore] for the verified limit), so this screen does two things
/// together: it asks the BMS for the current window, and it keeps every entry
/// it has ever seen in local, de-duplicated storage. The list can therefore grow
/// past what one fetch returns and is browsable offline. Rows are revealed a
/// page at a time as the user scrolls, so a history of thousands never builds
/// at once.
class LogbookScreen extends StatefulWidget {
  /// Injectable for tests; defaults to the process-wide [LogbookStore.instance].
  final LogbookStore? store;

  /// Injectable device key for tests; otherwise resolved from the live
  /// connection, then from the last-connected device.
  final String? deviceIdOverride;

  const LogbookScreen({super.key, this.store, this.deviceIdOverride});

  @override
  State<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends State<LogbookScreen> {
  static const int _pageSize = 50;

  late final LogbookStore _store = widget.store ?? LogbookStore.instance;
  final _ble = BleBmsService();
  final _scroll = ScrollController();

  String? _deviceId;
  bool _resolvingDevice = true;
  bool _loading = true;
  bool _requesting = false;
  int _total = 0;
  List<LogbookRecord> _rows = const [];
  StreamSubscription<String>? _changeSub;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_resolveDevice());
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _resolveDevice() async {
    var id = widget.deviceIdOverride;
    id ??= _ble.connectedDevice?.remoteId.str;
    if (id == null || id.isEmpty) {
      try {
        id = await _ble.getLastDeviceId();
      } catch (_) {
        id = null;
      }
    }
    if (!mounted) return;
    final resolved = (id == null || id.isEmpty) ? null : id;
    setState(() {
      _deviceId = resolved;
      _resolvingDevice = false;
    });
    if (resolved == null) {
      setState(() => _loading = false);
      return;
    }
    _changeSub = _store.changes
        .where((device) => device == resolved)
        .listen((_) => unawaited(_reload()));
    await _reload();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // Load the next page before the user reaches the very bottom so scrolling
    // stays smooth; _loadMore is a no-op once everything is shown.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      unawaited(_loadMore());
    }
  }

  Future<void> _reload() async {
    final id = _deviceId;
    if (id == null) return;
    final total = await _store.count(id);
    final first = await _store.readPage(id, offset: 0, limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _total = total;
      _rows = first;
      _loading = false;
    });
  }

  bool _loadingMore = false;

  Future<void> _loadMore() async {
    final id = _deviceId;
    if (id == null || _loadingMore || _rows.length >= _total) return;
    _loadingMore = true;
    final next = await _store.readPage(id, offset: _rows.length, limit: _pageSize);
    if (!mounted) {
      _loadingMore = false;
      return;
    }
    setState(() => _rows = [..._rows, ...next]);
    _loadingMore = false;
  }

  Future<void> _retrieve() async {
    setState(() => _requesting = true);
    final ok = await _ble.requestLogbook();
    if (!mounted) return;
    setState(() => _requesting = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not request the logbook — connect to a JK-BMS first.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    // The 0x05 frame arrives asynchronously and the service merges it into the
    // store, whose change stream reloads this list. Reload once now as well so
    // the count is honest even if the frame is a duplicate that changes nothing.
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF090D10) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        title: const Text(
          'LOGBOOK',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.4),
        ),
      ),
      body: JkAmbientBackground(
        child: RefreshIndicator(
          onRefresh: _retrieve,
          color: const Color(0xFF10B981),
          backgroundColor: cardBg,
          child: Builder(
            builder: (context) {
              final loading = _resolvingDevice || _loading;
              final hasMore = _rows.length < _total;
              final showNoDevice = !loading && _deviceId == null;
              final showEmpty = !loading && _deviceId != null && _rows.isEmpty;

              int itemCount;
              if (loading) {
                itemCount = 1 + 4; // header + skeleton rows
              } else if (showNoDevice || showEmpty) {
                itemCount = 2; // header + message
              } else {
                itemCount = 1 + _rows.length + (hasMore ? 1 : 0);
              }

              return ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _HeaderCard(
                      isDark: isDark,
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textPrimary: textPrimary,
                      total: _total,
                      requesting: _requesting,
                      onRetrieve: _retrieve,
                    );
                  }
                  if (loading) {
                    return const _LogbookSkeletonRow();
                  }
                  if (showNoDevice) {
                    return const _MessageCard(
                      icon: Icons.bluetooth_disabled_rounded,
                      text: 'Connect to a JK-BMS to fetch its logbook. Anything already '
                          'collected stays readable here offline.',
                    );
                  }
                  if (showEmpty) {
                    return const _MessageCard(
                      icon: Icons.history_toggle_off_rounded,
                      text: 'No events stored yet. Connect to your JK-BMS and tap Refresh.',
                    );
                  }
                  final rowIndex = index - 1;
                  if (rowIndex >= _rows.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  return _LogbookRow(
                    index: rowIndex + 1,
                    record: _rows[rowIndex],
                    textPrimary: textPrimary,
                    borderColor: borderColor,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MessageCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF64748B), size: 32),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown while the stored logbook is read from disk. Mirrors
/// [_LogbookRow]'s geometry so the real rows do not reflow the list.
class _LogbookSkeletonRow extends StatelessWidget {
  const _LogbookSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JkSkeleton(width: 26, height: 26, borderRadius: 7),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                JkSkeleton(width: 156, height: 11, borderRadius: 4),
                SizedBox(height: 6),
                JkSkeleton(width: 78, height: 10, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final bool isDark;
  final Color cardBg;
  final Color borderColor;
  final Color textPrimary;
  final int total;
  final bool requesting;
  final VoidCallback onRetrieve;

  const _HeaderCard({
    required this.isDark,
    required this.cardBg,
    required this.borderColor,
    required this.textPrimary,
    required this.total,
    required this.requesting,
    required this.onRetrieve,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E2830).withValues(alpha: 0.6)
                      : const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history_rounded, color: Color(0xFF7C3AED), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Saved event history',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary)),
                    Text(
                      total == 1 ? '1 event stored on this device' : '$total events stored on this device',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: requesting ? null : onRetrieve,
                icon: requesting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 16),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'The BMS returns up to 50 events per read. Refresh to collect more; '
            'every event the app has seen is kept here and can be browsed offline.',
            style: TextStyle(fontSize: 11, height: 1.35, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _LogbookRow extends StatelessWidget {
  final int index;
  final LogbookRecord record;
  final Color textPrimary;
  final Color borderColor;

  const _LogbookRow({
    required this.index,
    required this.record,
    required this.textPrimary,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final known = record.name.isNotEmpty;
    final title = known
        ? record.name
        : 'Unknown event (0x${record.code.toRadixString(16).padLeft(2, '0').toUpperCase()})';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text('$index',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: known ? textPrimary : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  record.offsetLabel,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
