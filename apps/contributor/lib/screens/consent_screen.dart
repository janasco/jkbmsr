import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/consent.dart';
import '../services/consent_controller.dart';
import '../widgets/brand_mark.dart';

/// The blocking first-run consent screen (plan §3.1).
///
/// Opt-in with the default **off**: the accept button stays disabled until the
/// switch is turned on. It is shown by [ConsentGate] over the shell until the
/// user answers, and can be re-opened from Home after a decline.
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
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(child: const BrandMark(size: 72)),
            const SizedBox(height: 16),
            Text(
              ConsentStrings.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              ConsentStrings.intro,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            _BulletCard(
              title: ConsentStrings.collectedTitle,
              icon: Icons.upload_file_rounded,
              items: ConsentStrings.collected,
            ),
            const SizedBox(height: 12),
            _BulletCard(
              title: ConsentStrings.notCollectedTitle,
              icon: Icons.shield_outlined,
              items: ConsentStrings.notCollected,
            ),
            const SizedBox(height: 12),
            _BulletCard(
              title: ConsentStrings.detailsTitle,
              icon: Icons.info_outline_rounded,
              items: ConsentStrings.details,
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: SwitchListTile(
                value: _agreed,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _agreed = value),
                title: Text(ConsentStrings.optInLabel),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  (_agreed && !_saving) ? () => _decide(ConsentDecision.granted) : null,
              child: const Text(ConsentStrings.accept),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _saving ? null : () => _decide(ConsentDecision.declined),
              child: const Text(ConsentStrings.decline),
            ),
            const SizedBox(height: 8),
            Text(
              ConsentStrings.declineNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletCard extends StatelessWidget {
  const _BulletCard({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: theme.textTheme.bodyMedium),
                    Expanded(
                      child: Text(item, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
