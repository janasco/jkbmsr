import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_info.dart';

void main() {
  runApp(const ContributorApp());
}

/// Root widget for JK BMS Contributor.
class ContributorApp extends StatelessWidget {
  const ContributorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppInfo.brandColor),
      ),
      home: const HomeScreen(),
    );
  }
}
