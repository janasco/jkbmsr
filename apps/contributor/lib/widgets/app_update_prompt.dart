import 'package:flutter/material.dart';

import '../services/app_info.dart';
import '../services/app_update_service.dart';
import '../services/play_update_service.dart';

/// Startup update flow for JK BMS Contributor.
///
/// Contributor is distributed only through Google Play, so there is no APK
/// path: a Play-installed copy is offered Google Play In-App Updates (flexible
/// normally, or Play's immediate full-screen flow when the release is
/// high-priority), and any other install does nothing.
///
/// [contextProvider] is called after the async check so the dialog always uses
/// a live context.
Future<void> promptForAppUpdate({
  required BuildContext? Function() contextProvider,
  AppUpdateService? service,
}) async {
  final updateService = service ?? AppUpdateService();
  final decision = await updateService.check();

  final context = contextProvider();
  if (context == null || !context.mounted) return;

  switch (decision.route) {
    case AppUpdateRoute.none:
      return;
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

/// Play path, normal priority: flexible update. Play downloads in the
/// background while the app keeps working, then we ask for the restart that
/// installs it.
Future<void> _showPlayFlexiblePrompt(
    BuildContext context, AppUpdateService service) async {
  final start = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Update available'),
      content: Text(
          'A new version of ${AppInfo.appName} is available. Update now for the '
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
        content: Text('Restart ${AppInfo.appName} to finish installing the update.'),
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
      content: Text('Google Play will install the new version of ${AppInfo.appName} now.'),
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

/// Small in-app toast, matching the `ScaffoldMessenger` snackbars used
/// elsewhere in the app.
void _toast(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
    ),
  );
}
