import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

/// Live "Next update in m:ss" countdown for the battery dashboard.
///
/// The API reports `secondsUntilNextExpectedCheckIn` on the device object, but
/// it is a *snapshot*: re-rendering it unchanged for minutes would be wrong.
/// This widget converts that snapshot into an absolute target the moment it
/// receives it (see [didUpdateWidget]) and then ticks down locally once a
/// second. It never polls the API — the dashboard's own poll timer delivers a
/// fresh value and this widget resyncs from it.
///
/// Rendering rules, all deliberate:
///   * [secondsUntilNextExpectedCheckIn] == null → render nothing. The API
///     omits the field when the gateway has never reported telemetry, so there
///     is no cadence to count down to; inventing one would be a lie.
///   * [deviceStatus] == 'offline' → render nothing. An offline gateway is not
///     expected to check in, so a countdown would be misleading.
///   * reaches zero → "Due now" and stop ticking. Better an honest "Due now"
///     than a negative number or a silently invented new target; the next
///     refresh (or the user's pull-to-refresh) supplies the new interval.
class JKBMSRNextUpdateCountdown extends StatefulWidget {
  /// The API's snapshot of seconds until the gateway's next expected check-in,
  /// or null when the API omitted it.
  final int? secondsUntilNextExpectedCheckIn;

  /// The gateway's status string ('online'/'offline'/'warning'/'critical').
  final String? deviceStatus;

  const JKBMSRNextUpdateCountdown({
    Key? key,
    this.secondsUntilNextExpectedCheckIn,
    this.deviceStatus,
  }) : super(key: key);

  /// Whether a countdown can honestly be shown for these inputs. Shared with
  /// callers so the surrounding layout can omit its spacing entirely rather
  /// than leaving a gap where a hidden widget would sit.
  static bool shouldShow({int? secondsUntilNextExpectedCheckIn, String? deviceStatus}) {
    return secondsUntilNextExpectedCheckIn != null &&
        deviceStatus?.toLowerCase() != 'offline';
  }

  @override
  State<JKBMSRNextUpdateCountdown> createState() => _JKBMSRNextUpdateCountdownState();
}

class _JKBMSRNextUpdateCountdownState extends State<JKBMSRNextUpdateCountdown> {
  Timer? _timer;
  DateTime? _target;
  Duration _remaining = Duration.zero;

  bool get _eligible => JKBMSRNextUpdateCountdown.shouldShow(
        secondsUntilNextExpectedCheckIn: widget.secondsUntilNextExpectedCheckIn,
        deviceStatus: widget.deviceStatus,
      );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant JKBMSRNextUpdateCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A poll delivered new inputs (including null ⇄ value, or a fresh value
    // that means the gateway just checked in) — restart from the new snapshot
    // instead of trusting a target derived from the previous one. Unchanged
    // inputs must NOT reset the target, or every unrelated rebuild would
    // restart the countdown.
    if (oldWidget.secondsUntilNextExpectedCheckIn != widget.secondsUntilNextExpectedCheckIn ||
        oldWidget.deviceStatus != widget.deviceStatus) {
      _sync(notify: false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// (Re)builds the absolute target from the current snapshot and starts the
  /// one-second ticker. A no-op timer state for the ineligible cases.
  void _sync({bool notify = true}) {
    _timer?.cancel();
    _timer = null;

    if (!_eligible) {
      _target = null;
      _remaining = Duration.zero;
      if (notify && mounted) setState(() {});
      return;
    }

    // Clamp defensively: the server already floors this at 0, but a negative
    // value from an older/odd payload must read as "due now", not time-travel.
    final seconds = widget.secondsUntilNextExpectedCheckIn! < 0
        ? 0
        : widget.secondsUntilNextExpectedCheckIn!;
    _target = clock.now().add(Duration(seconds: seconds));
    _remaining = _target!.difference(clock.now());
    if (notify && mounted) setState(() {});

    if (_remaining <= Duration.zero) return; // already due; no ticker needed
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final target = _target;
    if (target == null || !mounted) return;
    final remaining = target.difference(clock.now());
    if (remaining <= Duration.zero) {
      // Hold at "Due now" and stop the ticker — the next refresh resupplies a
      // real interval. Cancelling here is also what prevents an indefinitely
      // running timer for a device that has quietly stopped reporting.
      _timer?.cancel();
      _timer = null;
      if (!mounted) return;
      setState(() => _remaining = Duration.zero);
      return;
    }
    setState(() => _remaining = remaining);
  }

  String get _label {
    final total = _remaining.inSeconds;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_eligible) return const SizedBox.shrink();

    final due = _remaining <= Duration.zero;
    final color = due ? context.colors.signal : context.colors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.update, size: 14, color: color),
        const SizedBox(width: JKBMSRTokens.space8),
        Flexible(
          child: Text.rich(
            TextSpan(
              style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.textSecondary),
              children: due
                  ? [
                      TextSpan(text: 'Due now', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                    ]
                  : [
                      const TextSpan(text: 'Next update in '),
                      TextSpan(text: _label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                    ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
