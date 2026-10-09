import 'package:flutter/material.dart';

import '../../../models/device_wifi_target.dart';
import '../../../widgets/shared/design_system/components.dart';
import '../../../widgets/shared/design_system/tokens.dart';
import '../../../widgets/shared/design_system/typography.dart';

/// Owner controls for a gateway's "offline" alert episode, rendered on the
/// per-gateway battery dashboard next to the check-in countdown.
///
/// The alert is a per-gateway condition, not a per-row one, so the controls
/// live on the gateway surface rather than the cross-device Alerts list. This
/// widget carries no show/hide of its own beyond [shouldShow]: callers decide
/// when to place it, and a healthy online gateway with no mute or
/// acknowledgement contributes nothing — the same self-suppressing pattern as
/// the BMS link banner.
///
/// It is deliberately stateless and takes plain callbacks: the screen owns the
/// loaded [WifiAlertState] and the in-flight flag, and reports the server's
/// echoed value back into that state on success. Nothing here flips
/// optimistically, so a failed call can never leave the switch claiming a
/// state the server never stored.
class OfflineAlertControls extends StatelessWidget {
  final WifiAlertState alert;

  /// True while any alert action for this gateway is in flight. Disables every
  /// control so a second tap can't race the first.
  final bool busy;

  final VoidCallback onAcknowledge;
  final VoidCallback onReenable;
  final ValueChanged<bool> onToggleMute;

  const OfflineAlertControls({
    Key? key,
    required this.alert,
    required this.busy,
    required this.onAcknowledge,
    required this.onReenable,
    required this.onToggleMute,
  }) : super(key: key);

  /// Whether the controls carry any signal at all for this gateway. False for a
  /// healthy, un-muted, never-acknowledged gateway (render nothing) and for an
  /// unknown state (`null`, e.g. the route failed to load).
  static bool shouldShow(WifiAlertState? alert) {
    if (alert == null) return false;
    return alert.active || alert.muted || alert.acknowledgedAt != null;
  }

  @override
  Widget build(BuildContext context) {
    // Defensive: callers are expected to gate on shouldShow, but rendering
    // nothing is always the safe answer for an absent or healthy state.
    if (!shouldShow(alert)) return const SizedBox.shrink();

    final acknowledged = alert.acknowledgedAt != null;
    final active = alert.active;

    final IconData icon;
    final JKBMSRAlertTone tone;
    final String title;
    final String message;

    if (active && !acknowledged) {
      icon = Icons.wifi_off;
      tone = JKBMSRAlertTone.warning;
      title = 'Gateway offline alert';
      final times = alert.count > 0
          ? "We've alerted you ${alert.count} time${alert.count == 1 ? '' : 's'}. "
          : '';
      message = "This gateway hasn't checked in. ${times}"
          "Acknowledge the outage to stop the repeat alerts while it recovers.";
    } else if (acknowledged) {
      icon = Icons.notifications_paused_outlined;
      tone = JKBMSRAlertTone.accent;
      title = 'Offline alerts acknowledged';
      message = "You won't be alerted about this outage again until it clears "
          'or you re-enable alerts.';
    } else {
      // Muted, no active episode.
      icon = Icons.notifications_off_outlined;
      tone = JKBMSRAlertTone.warning;
      title = 'Offline alerts muted';
      message = "You won't be alerted if this gateway goes offline. Unmute to "
          'be alerted again.';
    }

    return JKBMSRAlertBanner(
      tone: tone,
      icon: icon,
      title: title,
      message: message,
      details: [
        if (alert.muted) 'Offline alerts are muted for this gateway.',
        if (alert.lastSentAt != null && alert.lastSentAt!.isNotEmpty)
          'Last alert sent ${alert.lastSentAt}',
      ],
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (active && !acknowledged)
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                key: const ValueKey('offline-alert-acknowledge'),
                onPressed: busy ? null : onAcknowledge,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space16),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Acknowledge this outage'),
              ),
            ),
          if (acknowledged)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('offline-alert-reenable'),
                onPressed: busy ? null : onReenable,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space16),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Re-enable alerts'),
              ),
            ),
          // SwitchListTile paints its ink on the nearest Material ancestor, and
          // the banner wraps it in a coloured DecoratedBox — without this
          // transparent Material the framework asserts the toggle would be
          // invisible against it.
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('offline-alert-mute'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Mute offline alerts'),
              subtitle: Text(
                alert.muted
                    ? 'Muted — you will not be alerted for this gateway.'
                    : 'Silence offline alerts for this gateway.',
                style: JKBMSRTypography.bodySecondary,
              ),
              value: alert.muted,
              onChanged: busy ? null : onToggleMute,
            ),
          ),
        ],
      ),
    );
  }
}
