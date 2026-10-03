import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';
import '../services/play_update_service.dart';
import 'shared/design_system/components.dart';

/// Startup update flow, branched on how the app was installed.
///
/// * A **Play-installed** copy is offered Google Play In-App Updates — a
///   flexible prompt normally, or Play's immediate full-screen flow when the
///   release is high-priority. It is never sent to a website or an APK.
/// * A **sideloaded** copy keeps the existing one-tap direct-APK prompt.
/// * An **unknown** installer shows nothing.
///
/// [contextProvider] is called after the async check so the dialog always uses
/// a live context, matching the startup call site in `main.dart`.
Future<void> promptForAppUpdate({
  required BuildContext? Function() contextProvider,
  AppUpdateService? service,
}) async {
  final updateService = service ?? AppUpdateService();
  final decision = await updateService.check();
  if (decision.route == AppUpdateRoute.none) return;

  final context = contextProvider();
  if (context == null || !context.mounted) return;

  switch (decision.route) {
    case AppUpdateRoute.none:
      return;
    case AppUpdateRoute.sideloadApk:
      await _showSideloadPrompt(context, decision.version ?? '');
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

/// Sideload path, unchanged: our release channel's version + APK download.
Future<void> _showSideloadPrompt(BuildContext context, String latest) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Update available'),
      content: Text(
          'JK BMS Remote $latest is available. Update for the latest fixes and features.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await launchUrl(Uri.parse(AppUpdateService.downloadUrl),
                mode: LaunchMode.externalApplication);
          },
          child: const Text('Download'),
        ),
      ],
    ),
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
          'A new version of JK BMS Remote is available. Update now for the '
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
      JKBMSRToast.show(context,
          'Could not start the update. Please try again from Google Play.',
          isError: true);
    }
    return;
  }
  if (!context.mounted) return;

  if (result != PlayUpdateResult.success) {
    JKBMSRToast.show(
      context,
      result == PlayUpdateResult.userDenied
          ? 'Update cancelled.'
          : 'Could not start the update. Please try again from Google Play.',
      isError: result == PlayUpdateResult.failed,
    );
    return;
  }

  JKBMSRToast.show(context, 'Downloading the update in the background…');

  // Play reports progress on the install-state stream. Ask for a restart once
  // the download finishes; surface a failure rather than hanging silently.
  service.playInstallStateStream
      .firstWhere((status) =>
          status == PlayInstallStatus.downloaded ||
          status == PlayInstallStatus.failed)
      .then((status) async {
    if (!context.mounted) return;
    if (status == PlayInstallStatus.failed) {
      JKBMSRToast.show(
          context, 'The update download failed. Please try again from Google Play.',
          isError: true);
      return;
    }
    final restart = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update ready'),
        content: const Text(
            'Restart JK BMS Remote to finish installing the update.'),
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
          'Google Play will install the new version of JK BMS Remote now.'),
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
      JKBMSRToast.show(context,
          'Could not start the update. Please try again from Google Play.',
          isError: true);
    }
  } catch (_) {
    if (context.mounted) {
      JKBMSRToast.show(context,
          'Could not start the update. Please try again from Google Play.',
          isError: true);
    }
  }
}
