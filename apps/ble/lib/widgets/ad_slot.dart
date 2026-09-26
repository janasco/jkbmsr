import 'package:flutter/material.dart';

import '../services/ads_config.dart';
import '../services/entitlement_service.dart';

/// The ad placements that are allowed to exist. One kind today, on purpose:
/// a single, reviewable list beats a format that grows per surface.
enum AdSlotKind {
  /// Standard banner, for the bottom of a read-only status/history screen.
  banner,
}

/// The one and only place an ad is allowed to appear in this app.
///
/// Renders nothing at all unless [AdsConfig.mayShowAds] says so, which today
/// is never: no AdMob app id, no ad SDK, no ad-unit id. When the SDK is wired
/// later, this widget is the single place it has to be inserted, and the
/// entitlement, the build kill switch and the per-surface decision all keep
/// working unchanged.
///
/// Deliberate exclusions — do not add an [AdSlot] to any of these, whatever
/// the room left on screen:
///  * the Connect/Scanning flow (`devices_screen.dart`, `welcome_screen.dart`);
///  * the Control screen (`control_screen.dart`);
///  * the PIN dialog (`auth_pin_dialog.dart`);
///  * anything rendered while a BLE connection is being established,
///    connecting or disconnecting.
///
/// Ads belong on read-only status/history surfaces, where a user is already
/// looking at stored telemetry and no command can be mis-tapped.
class AdSlot extends StatelessWidget {
  const AdSlot({
    super.key,
    this.slot = AdSlotKind.banner,
    this.config = AdsConfig.current,
  });

  final AdSlotKind slot;

  /// Defaults to [AdsConfig.current] — the app-wide ad configuration. Tests
  /// pass a configured instance to exercise the enabled path, which is
  /// unreachable in a shipped build.
  final AdsConfig config;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EntitlementState>(
      valueListenable: EntitlementService.instance.changes,
      builder: (context, entitlement, _) {
        if (!config.mayShowAds(entitlement)) {
          // Nothing in the tree, no reserved height, no spacing: a disabled ad
          // slot must be invisible to layout, semantics and screen readers.
          return const SizedBox.shrink();
        }
        return _buildAd(config, slot);
      },
    );
  }

  /// Only reachable once ads are deliberately configured. This is the single
  /// line that gets replaced by the real SDK widget (for example
  /// `AdView(adUnitId: <ad unit id added to AdsConfig>, ...)`).
  Widget _buildAd(AdsConfig config, AdSlotKind slot) {
    return Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF334155)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Ad slot (${slot.name}) — SDK not wired',
        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
      ),
    );
  }
}
