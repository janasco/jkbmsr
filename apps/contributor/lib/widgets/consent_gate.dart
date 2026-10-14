import 'package:flutter/material.dart';

import '../screens/consent_screen.dart';
import '../services/consent_controller.dart';

/// The blocking first-run consent gate (plan §3.1).
///
/// It mounts the shell and covers it with [ConsentScreen] until the user has
/// answered. The shell mounting underneath (rather than being replaced) means a
/// returning user — and a test that only wants the shell — never pays for the
/// gate; the overlay is opaque and absorbs all input, so nothing behind it is
/// reachable or captured.
///
/// "Not loaded" is treated as "not yet answered", so the gate fails closed: no
/// capture can start until a decision is stored.
class ConsentGate extends StatelessWidget {
  const ConsentGate({super.key, required this.controller, required this.child});

  final ConsentController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConsentScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final answered = controller.isLoaded && controller.hasDecision;
          return Stack(
            children: [
              child,
              if (!answered)
                Positioned.fill(child: ConsentScreen(controller: controller)),
            ],
          );
        },
      ),
    );
  }
}
