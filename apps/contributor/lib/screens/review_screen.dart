import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/contribution.dart';
import '../models/contribution_selection.dart';
import '../services/contribution_export.dart';
import '../services/contribution_uploader.dart';
import '../widgets/app_surface.dart';

/// Review-before-submit (plan §3.4): the exact payload, with per-field opt-out.
///
/// It renders the **real document** — the values come from
/// `Contribution.toJson`, not from a parallel description — so a field that is
/// switched off is genuinely absent from the bytes that would be sent, and the
/// size shown is the size of those bytes.
///
/// Submitting posts exactly those bytes to the anonymous endpoint (plan §3.5)
/// and shows the returned receipt id; the fallback writes the same bytes to a
/// `.json` file and hands it to the OS share sheet, so a transport or server
/// failure never loses a contribution. A `400` is the exception: the document
/// itself is unreadable, so exporting it would fail the same way.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.contribution,
    this.rawSerial,
    this.consent,
    this.uploader,
    this.exporter,
    this.onSubmitted,
  });

  final Contribution contribution;

  /// The device serial as read from the BMS. Only used when the user opts in;
  /// it is never carried otherwise.
  final String? rawSerial;

  /// The consent record to stamp on the payload, when consent was granted.
  final ConsentRecord? consent;

  /// The anonymous POST client. Injected in tests so the real status handling
  /// is driven by a fake transport; defaults to the live endpoint.
  final ContributionUploader? uploader;

  /// The offline file writer + share sheet. Injected in tests so the write is
  /// exercised without a platform plugin.
  final ContributionExporter? exporter;

  /// Called when a submit succeeds, so the screen underneath can state that
  /// the capture was sent even if the user leaves with the system back gesture.
  final ValueChanged<SubmitReceipt>? onSubmitted;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final Set<String> _included =
      ContributionFields.defaults().map((f) => f.id).toSet();

  late final ContributionUploader _uploader =
      widget.uploader ?? ContributionUploader();
  late final ContributionExporter _exporter =
      widget.exporter ?? ContributionExporter();

  /// Serial is opt-in and off by default.
  bool _includeSerial = false;

  /// A submit or export is in flight; both actions are disabled meanwhile.
  _BusyAction _busy = _BusyAction.none;

  /// Optional Contributor code, typed by the donor. Empty means anonymous.
  String _accountCode = '';

  /// The receipt from a successful submit, if any.
  SubmitReceipt? _receipt;

  /// The reason the last submit failed, if it did.
  SubmitFailure? _failure;

  /// Set after a successful export, so the user knows the file exists.
  bool _exported = false;

  ContributionSelection get _selection => ContributionSelection(_included);

  /// The payload as it would be sent: consent stamped, serial applied, then
  /// the switched-off fields omitted.
  Contribution get _effective => widget.contribution
      .withSerial(widget.rawSerial, include: _includeSerial)
      .withConsent(widget.consent);

  /// The exact bytes to send — and the exact bytes the export writes. There is
  /// one string for both paths, so the fallback file is always the document the
  /// submit would have posted.
  String get _payload => _effective.encode(selection: _selection);

  /// Submits the payload. There is no automatic retry: a `429` is surfaced
  /// honestly rather than hammering the limiter. Transport and server failures
  /// leave the export path available; a `400` does not, because the same bytes
  /// would be refused again.
  Future<void> _onSubmitPressed() async {
    if (_busy != _BusyAction.none) return;
    setState(() {
      _busy = _BusyAction.submit;
      _failure = null;
      _exported = false;
    });

    final result = await _uploader.submit(_payload, accountCode: _accountCode);
    if (!mounted) return;
    final receipt = result.receipt;
    setState(() {
      _busy = _BusyAction.none;
      if (result.isSuccess) {
        _receipt = receipt;
        _failure = null;
      } else {
        _receipt = null;
        _failure = result.failure;
      }
    });
    if (receipt != null) widget.onSubmitted?.call(receipt);
  }

  /// The offline fallback: write the same payload to a file and share it.
  Future<void> _onExportPressed() async {
    if (_busy != _BusyAction.none) return;
    setState(() {
      _busy = _BusyAction.export;
      _exported = false;
    });

    try {
      await _exporter.exportAndShare(
        _payload,
        contributionId: _effective.contributionId,
        capturedAt: _effective.capturedAt,
      );
      if (!mounted) return;
      setState(() {
        _busy = _BusyAction.none;
        _exported = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = _BusyAction.none);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(SubmitStrings.exportFailed)),
      );
    }
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
    // Once a receipt exists the document has been sent, so the fields it
    // describes are frozen: editing them would only make the preview disagree
    // with what the server archived.
    final frozen = _receipt != null;

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
            AppSurface(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: SwitchListTile(
                value: _includeSerial,
                onChanged: widget.rawSerial == null ||
                        widget.rawSerial!.isEmpty ||
                        frozen
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
                enabled: !frozen,
                onToggle: (id, value) => setState(
                    () => value ? _included.add(id) : _included.remove(id)),
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
            if (_receipt != null) _SuccessCard(receipt: _receipt!, serialShared: _effective.redaction.serialNumber == 'shared'),
            if (_failure != null) ...[
              _FailureCard(failure: _failure!),
              const SizedBox(height: 16),
            ],
            if (_exported) ...[
              const _InfoCard(
                icon: Icons.file_download_done_rounded,
                title: SubmitStrings.exportSuccessTitle,
                body: SubmitStrings.exportSuccessBody,
              ),
              const SizedBox(height: 16),
            ],
            if (_receipt != null)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_receipt),
                child: const Text(SubmitStrings.done),
              )
            else ...[
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Contributor code (optional)',
                  helperText: 'Leave empty to stay anonymous.',
                ),
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                onChanged: (value) => setState(() => _accountCode = value.trim()),
              ),
              const SizedBox(height: 8),
              Text(
                'Linking means this capture, its BMS model and its serial hash are '
                'associated with your account, and it earns points you can use for '
                'Cloud Service. Points need the serial number, so leave that switched '
                'on if you want them.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy == _BusyAction.none ? _onSubmitPressed : null,
                child: _busy == _BusyAction.submit
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(ReviewStrings.submit),
              ),
              const SizedBox(height: 8),
              // A 400 means these exact bytes were unreadable, so exporting
              // them as a later send is not a fallback. Every other failure
              // keeps the file path.
              if (_failure?.kind != SubmitFailureKind.invalid) ...[
                OutlinedButton.icon(
                  onPressed: _busy == _BusyAction.none ? _onExportPressed : null,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(_busy == _BusyAction.export
                      ? SubmitStrings.exporting
                      : SubmitStrings.exportButton),
                ),
                const SizedBox(height: 8),
              ],
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text(ReviewStrings.discard),
              ),
            ],
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

/// Which action is in flight, so each button can show its own progress.
enum _BusyAction { none, submit, export }

/// Shown after a successful submit, carrying the server's receipt id.
class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.receipt, required this.serialShared});

  final SubmitReceipt receipt;

  /// Whether this capture carried the serial. Points are only credited when it
  /// does, so the zero-credit explanation depends on it.
  final bool serialShared;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    SubmitStrings.successTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              SubmitStrings.successBody,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
            if (receipt.linked) ...[
              const SizedBox(height: 8),
              // Stated only when it happened: an anonymous capture has nothing to
              // say about points, and a "0 points" line would read as a failure.
              Text(
                receipt.credited > 0
                    ? 'Linked to your account, ${receipt.credited} points added.'
                    : !serialShared
                        ? 'Linked to your account. No points: this capture did not include '
                            'the serial number, and points need it so one pack is not paid twice.'
                        : 'Linked to your account. No points this time: the daily limit or an '
                            'already credited pack.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              SubmitStrings.successReceiptLabel,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 2),
            SelectableText(
              SubmitStrings.successReceipt(receipt.id),
              style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown after a failed submit, with the honest reason and the export hint.
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.failure});

  final SubmitFailure failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    SubmitStrings.failureMessage(failure),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // A 400 means the server could not read the document at all, so the
            // same bytes exported to a file would be refused later too. The
            // export fallback is only honest for transport and server failures.
            if (failure.kind != SubmitFailureKind.invalid)
              Text(
                SubmitStrings.exportHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onErrorContainer),
              ),
          ],
        ),
      ),
    );
  }
}

/// A neutral confirmation card (e.g. "file ready to share").
class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSurface(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
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
    final scheme = theme.colorScheme;

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'What will be sent',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$sizeBytes bytes',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '$samples',
                  label: 'Samples',
                  icon: Icons.timeline_rounded,
                ),
              ),
              Expanded(
                child: StatTile(
                  value: '${rawFrames.length}',
                  label: 'Frames',
                  icon: Icons.layers_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 6),
          DetailRow(label: 'Fields included', value: '$included of $total'),
          DetailRow(label: 'Payload size', value: '$sizeBytes bytes'),
          DetailRow(
            label: 'Raw frames',
            value: _frameSummary,
            stacked: true,
          ),
          DetailRow(
            label: 'Serial number',
            value: serialShared ? 'shared' : 'withheld',
          ),
        ],
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
    required this.enabled,
    required this.onToggle,
  });

  final String title;
  final List<ContributionField> fields;
  final Map<String, dynamic> fullJson;
  final Set<String> included;
  final bool enabled;
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
        AppSurface(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final field in fields)
                CheckboxListTile(
                  dense: true,
                  value: included.contains(field.id),
                  onChanged: enabled
                      ? (value) => onToggle(field.id, value ?? false)
                      : null,
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
    return AppSurface(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ReviewStrings.omittedTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          for (final label in labels)
            Text('•  $label', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Compact, honest display of a payload value.
String _formatValue(Object? value) {
  if (value == null) return '-';
  if (value is bool) return value ? 'yes' : 'no';
  if (value is num) return value.toString();
  if (value is String) return value.isEmpty ? '-' : value;
  if (value is Iterable) {
    if (value.isEmpty) return '-';
    final list = value.toList(growable: false);
    if (list.every((e) => e is num)) {
      final head = list.take(4).join(', ');
      return list.length <= 4
          ? '[$head]'
          : '[$head, … ${list.length - 4} more]';
    }
    return '${list.length} items';
  }
  if (value is Map) return value.isEmpty ? '-' : '${value.length} entries';
  return value.toString();
}
