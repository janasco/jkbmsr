import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'motion_kit.dart';

class DiagnosticsExpandable extends StatefulWidget {
  final List<String> rawLogs;
  const DiagnosticsExpandable({super.key, required this.rawLogs});

  @override
  State<DiagnosticsExpandable> createState() => _DiagnosticsExpandableState();
}

class _DiagnosticsExpandableState extends State<DiagnosticsExpandable> {
  bool _expanded = false;

  void _copyLogs() {
    Clipboard.setData(ClipboardData(text: widget.rawLogs.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostics log copied to clipboard.'),
        backgroundColor: Color(0xFF10B981),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final terminalBg = isDark ? const Color(0xFF090D10) : const Color(0xFF0F172A);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(14),
      // Smooth height animation when the terminal expands/collapses.
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
                          color: isDark ? const Color(0xFF1E2830).withValues(alpha: 0.6) : const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.terminal_rounded, color: Color(0xFF0284C7), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Diagnostics',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary),
                          ),
                          const Text(
                            'Technical frame and runtime details',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Chevron rotates smoothly instead of swapping glyphs.
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            Container(
              height: 1,
              color: borderColor,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const PulseDot(color: Color(0xFF10B981), size: 6),
                    const SizedBox(width: 6),
                    const Text(
                      'LIVE BLE FRAME STREAM:',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.rawLogs.isEmpty ? null : _copyLogs,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: widget.rawLogs.isEmpty ? const Color(0xFF64748B).withValues(alpha: 0.4) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: terminalBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: widget.rawLogs.isEmpty
                  ? const Text(
                      'Awaiting frames from BMS hardware...',
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.rawLogs.length,
                      itemBuilder: (context, idx) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            widget.rawLogs[idx],
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Color(0xFF38BDF8),
                              height: 1.3,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
        ),
      ),
    );
  }
}
