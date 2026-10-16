import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_info.dart';
import 'services/consent_controller.dart';
import 'services/consent_store.dart';
import 'widgets/app_update_prompt.dart';
import 'widgets/consent_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the consent decision before the first frame, so a returning user goes
  // straight to the shell and a first-run user sees the gate without a flash.
  final consent = ConsentController(store: SharedPreferencesConsentStore());
  await consent.load();
  runApp(ContributorApp(consent: consent));
}

/// Root widget for JK BMS Contributor.
class ContributorApp extends StatefulWidget {
  const ContributorApp({super.key, this.consent});

  /// Injected by `main` with the persisted store. Left null for a widget test
  /// that only wants the shell: the fallback keeps everything local and never
  /// touches a platform plugin.
  final ConsentController? consent;

  static final ConsentController _fallback =
      ConsentController(store: InMemoryConsentStore());

  @override
  State<ContributorApp> createState() => _ContributorAppState();
}

class _ContributorAppState extends State<ContributorApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Prompt once per launch if Play has a newer build. Contributor is
    // Play-only: a non-Play install does nothing (no APK channel exists).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      promptForAppUpdate(
        contextProvider: () => _navigatorKey.currentContext,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppInfo.brandColor),
      ),
      home: ConsentGate(
        controller: widget.consent ?? ContributorApp._fallback,
        child: const HomeScreen(),
      ),
    );
  }
}
