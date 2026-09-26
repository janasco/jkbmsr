import 'package:flutter/material.dart';

/// Shown instead of the real app when CloneGuardService detects this
/// process is running inside an OS-level "Dual Apps"/"Clone Apps" secondary
/// profile. Deliberately self-contained (own MaterialApp, hardcoded colors,
/// no dependency on AuthStore/ThemeController/design-system extensions) —
/// this is the fallback path for a security check, so it must render
/// correctly before any other app service has initialized.
class ClonedInstanceScreen extends StatelessWidget {
  const ClonedInstanceScreen({Key? key}) : super(key: key);

  static const _canvas = Color(0xFF080B0E);
  static const _critical = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _canvas,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.block_rounded, color: _critical, size: 56),
                  SizedBox(height: 24),
                  Text(
                    "JKBMSR isn't supported in a cloned app",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    "This copy is running through your phone's \"Dual Apps\", "
                    "\"Clone Apps\", or \"App Twin\" feature. Please uninstall the "
                    "cloned copy from Settings, then open JKBMSR from your normal "
                    "home screen.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
