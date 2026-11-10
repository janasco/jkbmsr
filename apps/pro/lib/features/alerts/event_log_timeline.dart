import 'package:flutter/material.dart';

import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import 'event_log.dart';

/// A chronological history drawn as a timeline: one vertical spine with a
/// marker per entry, so the screen reads as "what happened, in order" rather
/// than as another table. Each row expands to its own detail.
class EventLogTimeline extends StatelessWidget {
  final List<EventLogEntry> entries;
  final Widget? header;
  final Widget? footer;
  final Widget? Function(EventLogEntry entry)? actionBuilder;

  const EventLogTimeline({
    Key? key,
    required this.entries,
    this.header,
    this.footer,
    this.actionBuilder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final headerCount = header == null ? 0 : 1;
    final footerCount = footer == null ? 0 : 1;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        JKBMSRTokens.space16,
        JKBMSRTokens.space8,
        JKBMSRTokens.space16,
        JKBMSRTokens.space24,
      ),
      itemCount: headerCount + entries.length + footerCount,
      itemBuilder: (context, index) {
        if (header != null && index == 0) return header!;
        final entryIndex = index - headerCount;
        if (entryIndex >= 0 && entryIndex < entries.length) {
          return EventLogEntryTile(
            key: ValueKey('event-log-${entries[entryIndex].id}'),
            entry: entries[entryIndex],
            isFirst: entryIndex == 0,
            isLast: entryIndex == entries.length - 1,
            action: actionBuilder?.call(entries[entryIndex]),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: JKBMSRTokens.space8),
          child: Center(child: footer!),
        );
      },
    );
  }
}

/// One entry: a marker on the shared spine on the left, a tappable summary
/// card on the right, and that entry's full detail underneath when expanded.
class EventLogEntryTile extends StatefulWidget {
  final EventLogEntry entry;
  final bool isFirst;
  final bool isLast;
  final Widget? action;

  const EventLogEntryTile({
    Key? key,
    required this.entry,
    required this.isFirst,
    required this.isLast,
    this.action,
  }) : super(key: key);

  @override
  State<EventLogEntryTile> createState() => _EventLogEntryTileState();
}

class _EventLogEntryTileState extends State<EventLogEntryTile> {
  bool _expanded = false;

  Color _accent(BuildContext context) {
    switch (widget.entry.kind) {
      case EventKind.alert:
        return widget.entry.severity == 'critical'
            ? context.colors.critical
            : context.colors.warning;
      case EventKind.bleSession:
        return context.colors.accent;
      case EventKind.otaUpdate:
        return context.colors.signal;
    }
  }

  IconData get _icon {
    switch (widget.entry.kind) {
      case EventKind.alert:
        return widget.entry.severity == 'critical'
            ? Icons.error_outline
            : Icons.warning_amber_rounded;
      case EventKind.bleSession:
        return Icons.bluetooth_connected;
      case EventKind.otaUpdate:
        return Icons.system_update_alt;
    }
  }

  String get _kindLabel {
    switch (widget.entry.kind) {
      case EventKind.alert:
        return 'Alert';
      case EventKind.bleSession:
        return 'BLE session';
      case EventKind.otaUpdate:
        return 'Firmware';
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    final entry = widget.entry;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSpine(context, accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: JKBMSRTokens.space12),
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.panel,
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
                  border: Border.all(color: context.colors.line),
                ),
                child: Material(
                  color: context.colors.panel,
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _toggle,
                    child: Padding(
                      padding: const EdgeInsets.all(JKBMSRTokens.space12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(context, entry),
                          if (_expanded) ...[
                            const SizedBox(height: JKBMSRTokens.space12),
                            Container(height: 1, color: context.colors.line),
                            const SizedBox(height: JKBMSRTokens.space12),
                            _buildDetail(context, entry),
                            if (widget.action != null) ...[
                              const SizedBox(height: JKBMSRTokens.space12),
                              widget.action!,
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // The spine is padded so the marker lines up with the card's first text
  // line; the top segment is omitted on the first entry and the bottom one on
  // the last, so the line has a visible start and end.
  Widget _buildSpine(BuildContext context, Color accent) {
    Widget line() => Container(width: 1.5, color: context.colors.line);

    return SizedBox(
      width: 28,
      child: Column(
        children: [
          SizedBox(height: 15, child: widget.isFirst ? null : line()),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Icon(_icon, size: 14, color: accent),
          ),
          Expanded(child: widget.isLast ? const SizedBox() : line()),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, EventLogEntry entry) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: JKBMSRTokens.space8,
                runSpacing: JKBMSRTokens.space2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _kindLabel.toUpperCase(),
                    style: JKBMSRTypography.label.copyWith(
                      color: _accent(context),
                      fontSize: 11.0,
                    ),
                  ),
                  Text(
                    formatEventLogTime(entry.rawTimestamp),
                    style: JKBMSRTypography.monoTechnical.copyWith(
                      fontSize: 11.0,
                      color: context.colors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space4),
              Text(
                entry.summary,
                style: JKBMSRTypography.bodySecondary.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: JKBMSRTokens.space8),
        Icon(
          _expanded ? Icons.expand_less : Icons.expand_more,
          size: 20,
          color: context.colors.textMuted,
        ),
      ],
    );
  }

  Widget _buildDetail(BuildContext context, EventLogEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final field in entry.fields)
          Padding(
            padding: const EdgeInsets.only(bottom: JKBMSRTokens.space8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.label,
                  style: JKBMSRTypography.label.copyWith(
                    color: context.colors.textMuted,
                    fontSize: 11.0,
                  ),
                ),
                const SizedBox(height: JKBMSRTokens.space2),
                Text(
                  field.value,
                  style: (field.mono
                          ? JKBMSRTypography.monoTechnical
                          : JKBMSRTypography.bodySecondary)
                      .copyWith(color: context.colors.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
