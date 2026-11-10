import 'package:flutter/material.dart';

import '../services/capture_service.dart';
import '../services/consent_controller.dart';
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
/// Nothing has been sent at this point, and the copy says so. The only way data
/// leaves the device is the review screen's Submit button.
class CaptureSuccessScreen extends StatelessWidget {
  const CaptureSuccessScreen({super.key, required this.outcome});

  final CaptureOutcome outcome;

  void _review(BuildContext context) {
    final contribution = outcome.contribution;
    if (contribution == null) return;
    final consent = ConsentScope.maybeOf(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(
          contribution: contribution,
          rawSerial: outcome.session?.deviceInfo?.serialNumber,
          consent: consent?.record,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final contribution = outcome.contribution!;
    final bms = contribution.bms;
    final cells =
        bms.cellCountReported ?? contribution.samples.last.cellVoltagesV.length;
    final serialShared = contribution.redaction.serialNumber == 'shared';

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
              'Contribution ready',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Real data from your pack. Nothing has been sent yet: you review '
              'it first and decide.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
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
                FilledButton.icon(
                  onPressed: () => _review(context),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review & contribute'),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Done'),
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
