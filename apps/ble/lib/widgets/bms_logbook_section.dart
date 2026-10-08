import 'package:flutter/material.dart';

import '../models/bms_models.dart';
import '../services/ble_service.dart';

/// The BMS's own on-board event log ("logbook"). This is genuine hardware
/// history, not app-side accumulation: it is fetched from the JK-BMS with
/// command 0xA1 and answered with JK02 frame type 0x05, exactly as the
/// community `syssi/esphome-jk-bms` reference and the OEM app both do.
///
/// The BMS does not send an absolute wall-clock time for an entry — only a
/// seconds offset, which `syssi` formats as `DdHHhMMmSSs`. It is presented
/// here the same way, as a relative elapsed time rather than a date.
class BmsLogbookSection extends StatefulWidget {
  final bool isConnected;

  const BmsLogbookSection({super.key, required this.isConnected});

  @override
  State<BmsLogbookSection> createState() => _BmsLogbookSectionState();
}

class _BmsLogbookSectionState extends State<BmsLogbookSection> {
  bool _expanded = false;
  bool _requesting = false;

  static String _fmtOffset(int seconds) {
    final d = seconds ~/ 86400;
    final rem = seconds % 86400;
    final h = rem ~/ 3600;
    final m = (rem % 3600) ~/ 60;
    final s = rem % 60;
    return '${d}d ${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  }

  Future<void> _retrieve() async {
    setState(() => _requesting = true);
    final ok = await BleBmsService().requestLogbook();
    if (!mounted) return;
    setState(() => _requesting = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not request the logbook — is a JK-BMS connected?'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    final ble = BleBmsService();

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(14),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Event history',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary)),
                            const Text(
                              "The BMS's own logbook",
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              Container(height: 1, color: borderColor),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Read the event log stored on the BMS itself.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: (widget.isConnected && !_requesting) ? _retrieve : null,
                    icon: _requesting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Retrieve'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF7C3AED),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              StreamBuilder<Jk02Logbook?>(
                stream: ble.logbookStream,
                initialData: ble.currentLogbook,
                builder: (context, snapshot) {
                  final logbook = snapshot.data;
                  if (logbook == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No logbook loaded yet — tap Retrieve to fetch it from the BMS.',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
                      ),
                    );
                  }
                  if (logbook.entries.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'The BMS reports no recorded events.',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int idx = 0; idx < logbook.entries.length; idx++)
                        _LogbookRow(
                          index: idx + 1,
                          entry: logbook.entries[idx],
                          textPrimary: textPrimary,
                          borderColor: borderColor,
                        ),
                      const SizedBox(height: 4),
                      Text(
                        '${logbook.entries.length} event${logbook.entries.length == 1 ? '' : 's'}'
                        '${logbook.logCount > logbook.entries.length ? ' of ${logbook.logCount}' : ''}'
                        " · times are the BMS's own relative clock",
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogbookRow extends StatelessWidget {
  final int index;
  final Jk02LogbookEntry entry;
  final Color textPrimary;
  final Color borderColor;

  const _LogbookRow({
    required this.index,
    required this.entry,
    required this.textPrimary,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final known = entry.name.isNotEmpty;
    final title = known ? entry.name : 'Unknown event (0x${entry.code.toRadixString(16).padLeft(2, '0').toUpperCase()})';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$index',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: known ? textPrimary : const Color(0xFF64748B))),
                Text(
                  _BmsLogbookSectionState._fmtOffset(entry.seconds),
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
