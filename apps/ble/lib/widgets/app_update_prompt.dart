import 'package:flutter/material.dart';

import '../services/app_update_service.dart';
import '../services/play_update_service.dart';
import 'software_update_modal.dart';

/// Startup (and manual) update flow for JK BMS Bluetooth, branched on how the
/// app was installed.
///
/// * A **Play-installed** copy is offered Google Play In-App Updates — a
///   flexible prompt normally, or Play's immediate full-screen flow when the
///   release is high-priority. It is never sent to the in-app APK download
///   (`SoftwareUpdateModal` / `SelfUpdate`), which Play policy forbids for a
///   Play-distributed copy.
/// * A **sideloaded** copy keeps the existing direct-APK path unchanged: the
///   `SoftwareUpdateModal` status/download screen.
/// * An **unknown** installer shows nothing.
///
/// [contextProvider] is called after the async check so the dialog always uses
/// a live context.
///
/// [manual] is set by the drawer's "Software Update" row. It changes only the
/// *nothing-to-offer* case: a manual check reports its outcome ("you're up to
/// date", or that the source could not be reached) instead of silently doing
/// nothing. Startup keeps the silent default.
Future<void> promptForAppUpdate({
  required BuildContext? Function() contextProvider,
  AppUpdateService? service,
  bool manual = false,
}) async {
  final updateService = service ?? AppUpdateService();
  final decision = await updateService.check();

  final context = contextProvider();
  if (context == null || !context.mounted) return;

  switch (decision.route) {
    case AppUpdateRoute.none:
      if (manual) _showNoUpdateFeedback(context, decision.noUpdate);
      return;
    case AppUpdateRoute.sideloadApk:
      await _showSideloadPrompt(context);
    case AppUpdateRoute.playFlexible:
      await _showPlayFlexiblePrompt(context, updateService);
    case AppUpdateRoute.playImmediate:
      await _showPlayImmediatePrompt(
        context,
        updateService,
        blocking: decision.blocking,
      );
  }
}

/// Feedback for a *manual* check that found nothing to offer. Reports the one
/// thing the check actually established: either the source answered and the
/// app is current, or the source could not be reached and no claim can be
/// made. Never turns an unverifiable check into "up to date".
void _showNoUpdateFeedback(BuildContext context, AppUpdateNoUpdate? outcome) {
  switch (outcome) {
    case AppUpdateNoUpdate.upToDate:
      _toast(context, "You're on the latest version.");
    case AppUpdateNoUpdate.unavailable:
    case null:
      _toast(
        context,
        "Couldn't check for updates right now. Please try again later.",
        isError: true,
      );
  }
}

/// Sideload path, unchanged: the existing in-app download + installer UI.
Future<void> _showSideloadPrompt(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => SoftwareUpdateModal(onClose: () => Navigator.pop(ctx)),
  );
}

/// Play path, normal priority: flexible update. Play downloads in the
/// background while the app keeps working, then we ask for the restart that
/// installs it.
Future<void> _showPlayFlexiblePrompt(
    BuildContext context, AppUpdateService service) async {
  final start = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Update available'),
      content: const Text(
          'A new version of JK BMS Bluetooth is available. Update now for the '
          'latest fixes and features.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update')),
      ],
    ),
  );
  if (start != true || !context.mounted) return;

  final PlayUpdateResult result;
  try {
    result = await service.startFlexibleUpdate();
  } catch (_) {
    if (context.mounted) {
      _toast(context,
          'Could not start the update. Please try again from Google Play.',
          isError: true);
    }
    return;
  }
  if (!context.mounted) return;

  if (result != PlayUpdateResult.success) {
    _toast(
      context,
      result == PlayUpdateResult.userDenied
          ? 'Update cancelled.'
          : 'Could not start the update. Please try again from Google Play.',
      isError: result == PlayUpdateResult.failed,
    );
    return;
  }

  _toast(context, 'Downloading the update in the background…');

  // Play reports progress on the install-state stream. Ask for a restart once
  // the download finishes; surface a failure rather than hanging silently.
  service.playInstallStateStream
      .firstWhere((status) =>
          status == PlayInstallStatus.downloaded ||
          status == PlayInstallStatus.failed)
      .then((status) async {
    if (!context.mounted) return;
    if (status == PlayInstallStatus.failed) {
      _toast(
          context, 'The update download failed. Please try again from Google Play.',
          isError: true);
      return;
    }
    final restart = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update ready'),
        content:
            const Text('Restart JK BMS Bluetooth to finish installing the update.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restart')),
        ],
      ),
    );
    if (restart == true && context.mounted) {
      await service.completeFlexibleUpdate();
    }
  }).catchError((_) {
    // Stream closed/unsupported — the update simply stays pending until the
    // next launch, which is the same graceful state as a cancelled download.
  });
}

/// Play path, blocking priority: immediate update. Play owns the full-screen
/// install UI; we only explain why the user cannot dismiss it.
Future<void> _showPlayImmediatePrompt(
  BuildContext context,
  AppUpdateService service, {
  required bool blocking,
}) async {
  final proceed = await showDialog<bool>(
    context: context,
    barrierDismissible: !blocking,
    builder: (ctx) => AlertDialog(
      title: Text(blocking ? 'Update required' : 'Update available'),
      content: const Text(
          'Google Play will install the new version of JK BMS Bluetooth now.'),
      actions: [
        if (!blocking)
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update now')),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return;

  try {
    final result = await service.performImmediateUpdate();
    if (result == PlayUpdateResult.failed && context.mounted) {
      _toast(context,
          'Could not start the update. Please try again from Google Play.',
          isError: true);
    }
  } catch (_) {
    if (context.mounted) {
      _toast(context,
          'Could not start the update. Please try again from Google Play.',
          isError: true);
    }
  }
}

/// Small in-app toast. Mirrors the `ScaffoldMessenger` snackbars the rest of
/// the app already uses (no shared toast component in this app).
void _toast(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      backgroundColor: isError ? const Color(0xFFEF4444) : null,
    ),
  );
}
