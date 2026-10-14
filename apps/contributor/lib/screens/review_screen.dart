import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/contribution.dart';
import '../models/contribution_selection.dart';

/// Review-before-submit (plan §3.4): the exact payload, with per-field opt-out.
///
/// It renders the **real document** — the values come from
/// `Contribution.toJson`, not from a parallel description — so a field that is
/// switched off is genuinely absent from the bytes that would be sent, and the
/// size shown is the size of those bytes.
///
/// It deliberately stops at [ReviewStrings.submit]: submit and export are
/// Phase 5, and [_onSubmitPressed] is the seam.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.contribution,
    this.rawSerial,
    this.consent,
  });

  final Contribution contribution;

  /// The device serial as read from the BMS. Only used when the user opts in;
  /// it is never carried otherwise.
  final String? rawSerial;

  /// The consent record to stamp on the payload, when consent was granted.
  final ConsentRecord? consent;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final Set<String> _included =
      ContributionFields.defaults().map((f) => f.id).toSet();

  /// Serial is opt-in and off by default.
  bool _includeSerial = false;

  ContributionSelection get _selection => ContributionSelection(_included);

  /// The payload as it would be sent: consent stamped, serial applied, then
  /// the switched-off fields omitted.
  Contribution get _effective => widget.contribution
      .withSerial(widget.rawSerial, include: _includeSerial)
      .withConsent(widget.consent);

  /// Phase 5 seam. Nothing is submitted from Phase 4.
  void _onSubmitPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(ReviewStrings.submitSeam)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = _effective;
    final selection = _selection;
    // The full document is only used to show each field's current value and to
    // distinguish "withheld" from "empty".
    final fullJson = effective.toJson();
    final trimmedJson = effective.toJson(selection: selection);
    final omitted = selection.omittedIn(fullJson).toSet();

    final selectedCount = _included.length;
    final totalCount = ContributionFields.all.length;

    return Scaffold(
      appBar: AppBar(title: const Text(ReviewStrings.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(ReviewStrings.intro, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            _SummaryCard(
              sizeBytes: effective.encodedBytes(selection: selection),
              samples: effective.samples.length,
              rawFrames: effective.rawFrames,
              included: selectedCount,
              total: totalCount,
              serialShared: effective.redaction.serialNumber == 'shared',
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: SwitchListTile(
                value: _includeSerial,
                onChanged: widget.rawSerial == null || widget.rawSerial!.isEmpty
                    ? null
                    : (value) => setState(() => _includeSerial = value),
                title: const Text(ReviewStrings.serialLabel),
                subtitle: Text(ReviewStrings.serialDescription),
              ),
            ),
            const SizedBox(height: 16),
            for (final group in _groups())
              _GroupSection(
                title: group,
                fields: ContributionFields.all
                    .where((f) => f.group == group)
                    .toList(growable: false),
                fullJson: fullJson,
                included: _included,
                onToggle: (id, value) =>
                    setState(() => value ? _included.add(id) : _included.remove(id)),
              ),
            if (omitted.isNotEmpty) ...[
              const SizedBox(height: 8),
              _OmittedCard(
                labels: [
                  for (final field in ContributionFields.all)
                    if (omitted.contains(field.id)) field.label,
                ],
              ),
            ],
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('View raw JSON'),
              childrenPadding: const EdgeInsets.all(12),
              children: [
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(trimmedJson),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _onSubmitPressed,
              child: const Text(ReviewStrings.submit),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text(ReviewStrings.discard),
            ),
          ],
        ),
      ),
    );
  }

  /// Stable, display-ordered groups.
  List<String> _groups() {
    final seen = <String>[];
    for (final field in ContributionFields.all) {
      if (!seen.contains(field.group)) seen.add(field.group);
    }
    return seen;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.sizeBytes,
    required this.samples,
    required this.rawFrames,
    required this.included,
    required this.total,
    required this.serialShared,
  });

  final int sizeBytes;
  final int samples;
  final List<RawFrame> rawFrames;
  final int included;
  final int total;
  final bool serialShared;

  String get _frameSummary {
    if (rawFrames.isEmpty) return 'none';
    final byType = <String, int>{};
    for (final f in rawFrames) {
      byType[f.frameType] = (byType[f.frameType] ?? 0) + 1;
    }
    final parts = byType.entries.map((e) => '${e.key} ×${e.value}').join(', ');
    return '${rawFrames.length} ($parts)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 130,
                child: Text(label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(value,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Payload size', '$sizeBytes bytes'),
            row('Fields included', '$included of $total'),
            row('Telemetry samples', '$samples'),
            row('Raw frames', _frameSummary),
            row('Serial number', serialShared ? 'shared' : 'withheld'),
          ],
        ),
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.title,
    required this.fields,
    required this.fullJson,
    required this.included,
    required this.onToggle,
  });

  final String title;
  final List<ContributionField> fields;
  final Map<String, dynamic> fullJson;
  final Set<String> included;
  final void Function(String id, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final field in fields)
                CheckboxListTile(
                  dense: true,
                  value: included.contains(field.id),
                  onChanged: (value) => onToggle(field.id, value ?? false),
                  title: Text(field.label),
                  subtitle: Text(
                    included.contains(field.id)
                        ? '${field.description}\n${_formatValue(field.valueFrom(fullJson))}'
                        : '${field.description}\nOmitted',
                  ),
                  isThreeLine: true,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OmittedCard extends StatelessWidget {
  const _OmittedCard({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ReviewStrings.omittedTitle,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            for (final label in labels)
              Text('•  $label', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Compact, honest display of a payload value.
String _formatValue(Object? value) {
  if (value == null) return '—';
  if (value is bool) return value ? 'yes' : 'no';
  if (value is num) return value.toString();
  if (value is String) return value.isEmpty ? '—' : value;
  if (value is Iterable) {
    if (value.isEmpty) return '—';
    final list = value.toList(growable: false);
    if (list.every((e) => e is num)) {
      final head = list.take(4).join(', ');
      return list.length <= 4
          ? '[$head]'
          : '[$head, … ${list.length - 4} more]';
    }
    return '${list.length} items';
  }
  if (value is Map) return value.isEmpty ? '—' : '${value.length} entries';
  return value.toString();
}
