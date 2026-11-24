import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/capture_service.dart';
import '../services/consent_controller.dart';
import '../services/contribution_export.dart';
import '../services/contribution_uploader.dart';
import '../theme/app_theme.dart';
import '../widgets/app_surface.dart';
import 'review_screen.dart';

/// Where a contributor lands the moment a capture completes.
///
/// This is a **separate route**, not a state of the capture screen, and that is
/// the point: while it is running the capture screen is a live instrument, and
/// the moment the data exists the user is finished with the instrument. The old
/// screen mixed the two — a spinner, then a list of field labels in its place —
/// which read like a log dump rather than like something was achieved.
///
/// Nothing has been sent when this screen first appears, and the copy says so.
/// The only way data leaves the device is the review screen's Submit button; a
/// successful submit carries its receipt back here, and the screen then states
/// that the capture was sent instead of offering the review again.
class CaptureSuccessScreen extends StatefulWidget {
  const CaptureSuccessScreen({
    super.key,
    required this.outcome,
    this.uploader,
    this.exporter,
  });

  final CaptureOutcome outcome;

  /// Injected in tests so a submit can be driven without the live endpoint.
  final ContributionUploader? uploader;

  /// Injected in tests, mirroring [ReviewScreen.exporter].
  final ContributionExporter? exporter;

  @override
  State<CaptureSuccessScreen> createState() => _CaptureSuccessScreenState();
}

class _CaptureSuccessScreenState extends State<CaptureSuccessScreen> {
  /// Set once a submit succeeds, so this screen can never return to
  /// "Nothing has been sent yet" after the review screen is popped.
  SubmitReceipt? _receipt;

  void _onSubmitted(SubmitReceipt receipt) {
    if (!mounted) return;
    setState(() => _receipt = receipt);
  }

  Future<void> _review() async {
    final contribution = widget.outcome.contribution;
    if (contribution == null) return;
    final consent = ConsentScope.maybeOf(context);
    final receipt = await Navigator.of(context).push<SubmitReceipt>(
      MaterialPageRoute<SubmitReceipt>(
        builder: (_) => ReviewScreen(
          contribution: contribution,
          rawSerial: widget.outcome.session?.deviceInfo?.serialNumber,
          consent: consent?.record,
          uploader: widget.uploader,
          exporter: widget.exporter,
          onSubmitted: _onSubmitted,
        ),
      ),
    );
    if (receipt != null && mounted) {
      setState(() => _receipt = receipt);
    }
  }

  /// Discarding is destructive, so it asks first. "Done" used to pop silently,
  /// which read as "finish" and threw away 30 seconds of capture.
  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(SubmitStrings.discardConfirmTitle),
        content: const Text(SubmitStrings.discardConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(SubmitStrings.discardConfirmKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(SubmitStrings.discardCapture),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final contribution = widget.outcome.contribution!;
    final bms = contribution.bms;
    final cells =
        bms.cellCountReported ?? contribution.samples.last.cellVoltagesV.length;
    final serialShared = contribution.redaction.serialNumber == 'shared';
    final receipt = _receipt;
    final sent = receipt != null;

    // No app bar. A lone close button floating in the top-right corner with no
    // title above it reads as a stray control - in a listing screenshot it looked
    // like a banner - and it duplicated the two exits pinned at the bottom. The
    // system back gesture still pops the route.
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            const SizedBox(height: 8),
            const Center(child: _SuccessBadge()),
            const SizedBox(height: 24),
            Text(
              sent ? SubmitStrings.sentTitle : 'Contribution ready',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              sent
                  ? receipt.linked
                      ? 'Your capture was sent and linked to your account. Receipt '
                          '${receipt.id}.'
                      : 'Your capture was sent and stored anonymously. Receipt '
                          '${receipt.id}.'
                  : 'Real data from your pack. Nothing has been sent yet: you review '
                      'it first and decide.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (widget.outcome.cancelled) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.stop_circle_outlined,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      CaptureStrings.stoppedEarly,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            AppSurface(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          value: '${contribution.samples.length}',
                          label: 'Samples',
                          icon: Icons.timeline_rounded,
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          value: '${contribution.rawFrames.length}',
                          label: 'Frames',
                          icon: Icons.layers_rounded,
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          value: '$cells',
                          label: 'Cells',
                          icon: Icons.view_module_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 6),
                  DetailRow(
                    label: 'Model',
                    value: bms.modelName.isEmpty ? 'Unknown' : bms.modelName,
                    emphasis: true,
                  ),
                  DetailRow(label: 'Layout', value: bms.layout),
                  DetailRow(
                    label: 'Firmware',
                    value:
                        bms.softwareVersion.isEmpty ? '-' : bms.softwareVersion,
                  ),
                  DetailRow(
                    label: 'Serial',
                    value: serialShared ? 'shared' : 'withheld',
                  ),
                  DetailRow(
                    label: 'Payload',
                    value: '${contribution.encodedBytes()} bytes',
                  ),
                ],
              ),
            ),
            if (!sent) ...[
              const SizedBox(height: 24),
              Text('What happens next', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              const _NextStep(
                number: '1',
                text:
                    'Review the exact payload, field by field, and switch off anything '
                    'you would rather not share.',
              ),
              const _NextStep(
                number: '2',
                text:
                    'The battery serial stays withheld unless you turn it on. The '
                    'Bluetooth address is always reduced to its vendor prefix.',
              ),
              const _NextStep(
                number: '3',
                text:
                    'Submit anonymously. There is no account, no sign-in and no device '
                    'identifier attached.',
              ),
            ],
          ],
        ),
      ),
      // The primary action never scrolls away: the whole point of this screen is
      // the one decision it asks for.
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top:
                BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sent)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(SubmitStrings.done),
                  )
                else
                  FilledButton.icon(
                    onPressed: _review,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Review & contribute'),
                  ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    // A submitted capture cannot be discarded: the review
                    // screen already sent it.
                    if (!sent)
                      TextButton(
                        onPressed: _discard,
                        child: const Text(SubmitStrings.discardCapture),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Capture another pack'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A check that grows into place once, so the screen has a moment of arrival
/// without an endless animation behind the content.
class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutBack,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accent[0].withValues(alpha: 0.24),
              AppTheme.accent[1].withValues(alpha: 0.16),
            ],
          ),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        ),
        child: Icon(
          Icons.check_rounded,
          size: 46,
          color: scheme.primary,
        ),
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
