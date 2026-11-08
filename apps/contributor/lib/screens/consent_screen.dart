import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/consent.dart';
import '../services/consent_controller.dart';
import '../widgets/app_surface.dart';
import '../widgets/brand_mark.dart';

/// The blocking first-run consent screen (plan §3.1).
///
/// Opt-in with the default **off**: the accept button stays disabled until the
/// switch is turned on. It is shown by [ConsentGate] over the shell until the
/// user answers, and can be re-opened from Home after a decline.
///
/// The decision is **pinned to the bottom** rather than sitting at the end of the
/// scroll. This is the one screen where the user must be able to act without
/// hunting, and an accept button that is 900 px down reads as if there is
/// something to hide.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, this.controller, this.onDecided});

  /// Injected by the gate; otherwise read from the nearest [ConsentScope].
  final ConsentController? controller;

  /// Called after a decision is persisted.
  final VoidCallback? onDecided;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  /// Privacy-first default: off.
  bool _agreed = false;
  bool _saving = false;

  ConsentController get _consent =>
      widget.controller ?? ConsentScope.of(context);

  Future<void> _decide(ConsentDecision decision) async {
    if (_saving) return;
    setState(() => _saving = true);
    await _consent.decide(decision);
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onDecided?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.surfaceContainerHigh,
                      scheme.surfaceContainerLow,
                    ],
                  ),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: const BrandMark(size: 56),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              ConsentStrings.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              ConsentStrings.intro,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 26),
            _ConsentSection(
              title: ConsentStrings.collectedTitle,
              icon: Icons.upload_file_rounded,
              items: ConsentStrings.collected,
            ),
            const SizedBox(height: 12),
            _ConsentSection(
              title: ConsentStrings.notCollectedTitle,
              icon: Icons.shield_outlined,
              items: ConsentStrings.notCollected,
              reassuring: true,
            ),
            const SizedBox(height: 12),
            _ConsentSection(
              title: ConsentStrings.detailsTitle,
              icon: Icons.info_outline_rounded,
              items: ConsentStrings.details,
            ),
            const SizedBox(height: 14),
            Text(
              ConsentStrings.declineNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
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
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppSurface(
                  radius: 18,
                  color: scheme.surfaceContainerLow,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    value: _agreed,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _agreed = value),
                    title: Text(
                      ConsentStrings.optInLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: (_agreed && !_saving)
                      ? () => _decide(ConsentDecision.granted)
                      : null,
                  child: const Text(ConsentStrings.accept),
                ),
                TextButton(
                  onPressed:
                      _saving ? null : () => _decide(ConsentDecision.declined),
                  child: const Text(ConsentStrings.decline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One titled block of consent copy.
///
/// The "what we never collect" block is tinted and carries a shield; everything
/// else is neutral. That is the one reassurance a stranger is looking for, and it
/// should not have to be found by reading three paragraphs.
class _ConsentSection extends StatelessWidget {
  const _ConsentSection({
    required this.title,
    required this.icon,
    required this.items,
    this.reassuring = false,
  });

  final String title;
  final IconData icon;
  final List<String> items;
  final bool reassuring;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = scheme.primary;

    return AppSurface(
      color: reassuring ? accent.withValues(alpha: 0.06) : null,
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: reassuring
                      ? accent.withValues(alpha: 0.14)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: reassuring ? accent : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: reassuring ? accent : scheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
